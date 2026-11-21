class_name MobileUI
extends Node
## Pixelorama's touch-first layout.
##
## The canvas takes up (almost) the whole screen. A slim top bar holds the menu, project,
## undo/redo and layers buttons, and a bottom bar holds the color and the most used tools.
## Everything else (colors, tool options, layers & frames, all tools, every other panel) lives in
## slide-up sheets, so nothing gets crowded.
##
## No feature is reimplemented: the existing panels and menus are simply moved into the sheets,
## so all of Pixelorama's functionality, shortcuts and extensions keep working.

## The tools that have a permanent button in the bottom bar.
const QUICK_TOOLS: Array[String] = ["Pencil", "Eraser", "Bucket", "ColorPicker"]
## The panels that can be opened from the "Panels" page of the menu.
const PANEL_NAMES: Array[String] = [
	"Canvas Preview",
	"Reference Images",
	"Perspective Editor",
	"Recorder",
	"Layer FX",
	"Tiles",
	"3D Object Tree",
	"Second Canvas",
]
## The interface size multipliers that can be chosen from the menu.
const SCALE_FACTORS: Array[float] = [0.7, 0.8, 0.9, 1.0, 1.15, 1.3, 1.5, 1.75, 2.0]

var _main: Control
var _menu_and_ui: VBoxContainer
var _dock: DockableContainer
var _top_menu: Control
var _touch_theme: Theme
## Invisible node that keeps the panels that are not shown in any sheet.
var _holder: Control
var _panels: Dictionary[String, Control] = {}
var _sheet_layer: Control
var _sheets: Array[MobileSheet] = []

var _top_bar: PanelContainer
var _project_button: Button
var _undo_button: Button
var _redo_button: Button
var _bottom_bar: PanelContainer
var _color_button: Button
var _color_swatch: Panel
var _quick_buttons: Dictionary[String, Button] = {}
var _more_button: Button
var _options_button: Button
var _layers_button: Button

var _menu_sheet: MobileSheet
var _menu: MobileMenu
var _color_sheet: MobileSheet
var _color_tabs: Array[Button] = []
var _options_sheet: MobileSheet
var _layers_sheet: MobileSheet
var _tools_sheet: MobileSheet
var _tools_grid: GridContainer
var _panel_sheet: MobileSheet
var _poll_timer := Timer.new()


## The scale that makes the interface about as big as the standard Android density-independent
## units (so buttons are comfortable to tap), before the user's own size preference.
static func get_base_display_scale() -> float:
	var forced := OS.get_environment("PIXELORAMA_UI_SCALE")
	if forced.is_valid_float():
		return forced.to_float()
	var dpi := DisplayServer.screen_get_dpi()
	var screen_size := DisplayServer.screen_get_size()
	var short_side := mini(screen_size.x, screen_size.y)
	var display_scale := 1.0
	if dpi > 0:
		display_scale = clampf(dpi / 160.0, 1.0, 4.0)
	# Make sure there's enough room across the screen.
	if short_side / display_scale < 340.0:
		display_scale = short_side / 340.0
	return maxf(snappedf(display_scale, 0.05), 1.0)


## The final scale, including the interface size chosen by the user.
static func compute_display_scale() -> float:
	var factor: float = Global.config_cache.get_value("preferences", "mobile_ui_scale", 1.0)
	return snappedf(get_base_display_scale() * factor, 0.05)


## Saves which layout to use, and tells the user that Pixelorama has to be restarted.
static func request_layout_switch(parent: Node, use_mobile_layout: bool) -> void:
	Global.config_cache.set_value("preferences", "mobile_ui", use_mobile_layout)
	Global.config_cache.save(Global.CONFIG_PATH)
	var dialog := AcceptDialog.new()
	dialog.title = "Pixelorama"
	if use_mobile_layout:
		dialog.dialog_text = parent.tr("Restart Pixelorama to switch to the touch layout.")
	else:
		dialog.dialog_text = parent.tr(
			"Restart Pixelorama to switch to the classic desktop layout."
		)
	dialog.visibility_changed.connect(
		func() -> void:
			if not dialog.visible:
				dialog.queue_free()
	)
	parent.add_child(dialog)
	dialog.popup_centered_clamped(Vector2i(420, 140))


func _ready() -> void:
	name = "MobileUI"
	_main = Global.control
	_menu_and_ui = _main.get_node("MenuAndUI") as VBoxContainer
	_top_menu = Global.top_menu_container
	_dock = _main.main_ui
	_touch_theme = MobileStyle.make_touch_theme(_main.theme)
	var dialogs := _main.get_node_or_null("Dialogs") as Control
	if dialogs:
		dialogs.theme = _touch_theme
	_prepare_dock()
	_build_sheets()
	_build_top_bar()
	_build_bottom_bar()
	_connect_signals()
	_refresh_all()
	_poll_timer.wait_time = 0.3
	_poll_timer.timeout.connect(_poll_state)
	add_child(_poll_timer)
	_poll_timer.start()
	await Global.pixelorama_opened
	if not Global.single_tool_mode:
		Global.single_tool_mode = true
	_refresh_all()


## Called when the Android back button is pressed.
## Returns [code]true[/code] if the request was used up by the mobile UI.
func handle_back_request() -> bool:
	for sheet in _sheets:
		if sheet.is_open:
			if sheet == _menu_sheet and _menu.can_go_back():
				_menu.go_back()
			else:
				sheet.close()
			return true
	return false


func is_any_sheet_open() -> bool:
	for sheet in _sheets:
		if sheet.is_open:
			return true
	return false


#region Setup
func _prepare_dock() -> void:
	# Show only the canvas in the dock. The layout is a new one that is never saved,
	# so the desktop layouts of the user are left untouched.
	var layout := DockableLayout.new()
	var root_panel := DockableLayoutPanel.new()
	root_panel.push_name("Main Canvas")
	layout.root = root_panel
	layout.save_on_change = false
	_dock.layout = layout
	_dock.hide_single_tab = true

	_holder = Control.new()
	_holder.name = "PanelHolder"
	_holder.visible = false
	add_child(_holder)
	for child in _dock.get_children():
		if not child is Control or String(child.name).begins_with("_"):
			continue
		if child.name == &"Main Canvas":
			continue
		_panels[String(child.name)] = child
		child.reparent(_holder, false)

	_top_menu.visible = false
	var tabs_container := _main.find_child("TabsContainer") as Control
	if tabs_container:
		tabs_container.visible = false
	Global.show_rulers = false
	_top_menu.view_menu.set_item_checked(Global.ViewMenu.SHOW_RULERS, false)


func _build_sheets() -> void:
	_sheet_layer = Control.new()
	_sheet_layer.name = "MobileSheets"
	_sheet_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet_layer.theme = _touch_theme
	_dock.get_parent().add_child(_sheet_layer)
	_sheet_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Menu
	_menu_sheet = _create_sheet("Menu", 0.94)
	_menu = MobileMenu.new()
	_menu.top_menu = _top_menu
	_menu.panel_names = PANEL_NAMES
	_menu.panel_available = _is_panel_relevant
	_menu.page_changed.connect(_on_menu_page_changed)
	_menu.close_requested.connect(_menu_sheet.close)
	_menu.panel_requested.connect(open_panel)
	_menu.ui_scale_change_requested.connect(_on_ui_scale_change_requested)
	_menu.classic_layout_requested.connect(_on_classic_layout_requested)
	_menu_sheet.back_pressed.connect(_menu.go_back)
	_menu_sheet.set_content(_menu, 4)

	# Colors
	_color_sheet = _create_sheet("Colors", 0.7)
	var color_box := VBoxContainer.new()
	var switcher := HBoxContainer.new()
	switcher.add_theme_constant_override("separation", 6)
	color_box.add_child(switcher)
	var color_panels: Array[Control] = [_panels["Color Picker"], _panels["Palettes"]]
	var color_names: Array[String] = ["Picker", "Palettes"]
	for i in color_names.size():
		var tab := Button.new()
		tab.text = tr(color_names[i])
		tab.toggle_mode = true
		tab.focus_mode = Control.FOCUS_NONE
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.custom_minimum_size.y = 44
		tab.pressed.connect(_show_color_tab.bind(i))
		switcher.add_child(tab)
		_color_tabs.append(tab)
		color_panels[i].reparent(color_box, false)
		color_panels[i].size_flags_vertical = Control.SIZE_EXPAND_FILL
	_color_sheet.set_content(color_box, 8)
	_show_color_tab(0)

	# Tool options
	_options_sheet = _create_sheet("Tool options", 0.7)
	var options_scroll := ScrollContainer.new()
	options_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var options_box := VBoxContainer.new()
	options_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options_box.add_theme_constant_override("separation", 8)
	options_scroll.add_child(options_box)
	options_box.add_child(_build_action_strip())
	var global_options := _panels["Global Tool Options"]
	global_options.reparent(options_box, false)
	_enlarge_touch_targets(global_options)
	var global_scroll := global_options.get_node_or_null("ScrollContainer") as ScrollContainer
	if global_scroll:
		global_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var left_options := _panels["Left Tool Options"] as ScrollContainer
	left_options.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_options.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_options.reparent(options_box, false)
	_options_sheet.set_content(options_scroll, 8)

	# Layers & frames
	_layers_sheet = _create_sheet("Layers & frames", 0.72)
	_adapt_timeline(_panels["Animation Timeline"])
	_layers_sheet.set_content(_panels["Animation Timeline"], 4, null, true)

	# All tools
	_tools_sheet = _create_sheet("Tools", 0.62)
	var tools_scroll := ScrollContainer.new()
	tools_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tools_grid = GridContainer.new()
	_tools_grid.columns = 4
	_tools_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tools_grid.add_theme_constant_override("h_separation", 6)
	_tools_grid.add_theme_constant_override("v_separation", 6)
	tools_scroll.add_child(_tools_grid)
	_tools_sheet.set_content(tools_scroll, 10)
	_tools_sheet.opened.connect(_populate_tools_grid)

	# Any other panel
	_panel_sheet = _create_sheet("", 0.7)


## Makes the timeline fit a narrow screen: the layer buttons go above the frame and playback
## buttons (instead of next to them), and the small buttons are made easier to tap.
## The buttons themselves are only moved, so everything keeps working.
func _adapt_timeline(timeline: Control) -> void:
	var buttons_path := "TimelineContainer/TimelineButtons"
	var animation_path := (
		buttons_path
		+ "/VBoxContainer/AnimationToolsScrollContainer/AnimationTools/MarginContainer"
		+ "/AnimationButtons"
	)
	var timeline_buttons := timeline.get_node_or_null(buttons_path) as Control
	if timeline_buttons:
		_replace_with_vbox(timeline_buttons)
	var animation_buttons := timeline.get_node_or_null(animation_path) as Control
	if animation_buttons:
		_replace_with_vbox(animation_buttons)
	var animation_tools := (
		timeline.get_node_or_null(
			buttons_path + "/VBoxContainer/AnimationToolsScrollContainer/AnimationTools"
		)
		as Control
	)
	if animation_tools:
		animation_tools.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var new_buttons := timeline.get_node_or_null(buttons_path)
	if new_buttons:
		_enlarge_touch_targets(new_buttons, 38.0)


## Swaps a horizontal box for a vertical one, moving all of its children over.
func _replace_with_vbox(box: Control) -> void:
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = box.size_flags_horizontal
	vbox.size_flags_vertical = box.size_flags_vertical
	if box.has_theme_constant_override("separation"):
		vbox.add_theme_constant_override("separation", box.get_theme_constant("separation"))
	var parent := box.get_parent()
	var index := box.get_index()
	var box_name := box.name
	for child in box.get_children():
		child.reparent(vbox, false)
	parent.remove_child(box)
	box.queue_free()
	parent.add_child(vbox)
	parent.move_child(vbox, index)
	vbox.name = box_name


## Raises the minimum size of the small icon buttons inside [param root] to [param target].
func _enlarge_touch_targets(root: Node, target := 44.0) -> void:
	for node in root.find_children("*", "BaseButton", true, false):
		var control := node as Control
		if control.custom_minimum_size.x > 0.0 and control.custom_minimum_size.x < target:
			control.custom_minimum_size.x = target
		if control.custom_minimum_size.y > 0.0 and control.custom_minimum_size.y < target:
			control.custom_minimum_size.y = target


func _create_sheet(sheet_title: String, ratio: float) -> MobileSheet:
	var sheet := MobileSheet.new()
	sheet.title = sheet_title
	sheet.height_ratio = ratio
	_sheet_layer.add_child(sheet)
	sheet.opened.connect(_on_sheet_opened.bind(sheet))
	_sheets.append(sheet)
	return sheet


func _build_action_strip() -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	var modifiers := {"Shift": KEY_SHIFT, "Ctrl": KEY_CTRL, "Alt": KEY_ALT}
	for modifier_name: String in modifiers:
		var button := Button.new()
		button.text = modifier_name
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(64, 44)
		MobileStyle.style_button(button, false, 10, 12, true)
		button.toggled.connect(_on_modifier_toggled.bind(modifiers[modifier_name]))
		flow.add_child(button)
	var actions := {
		"Copy": Global.EditMenu.COPY,
		"Cut": Global.EditMenu.CUT,
		"Paste": Global.EditMenu.PASTE,
		"Delete": Global.EditMenu.DELETE,
	}
	for action_name: String in actions:
		var button := Button.new()
		button.text = tr(action_name)
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(64, 44)
		MobileStyle.style_button(button, false, 10, 12, true)
		button.pressed.connect(_top_menu.edit_menu_id_pressed.bind(actions[action_name]))
		flow.add_child(button)
	return flow


func _build_top_bar() -> void:
	_top_bar = PanelContainer.new()
	_top_bar.name = "MobileTopBar"
	_top_bar.theme = _touch_theme
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 2)
	_top_bar.add_child(hbox)

	var menu_button := MobileStyle.make_icon_button("menu")
	menu_button.pressed.connect(open_menu)
	hbox.add_child(menu_button)

	_project_button = Button.new()
	_project_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_project_button.clip_text = true
	_project_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_project_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_project_button.custom_minimum_size.y = MobileStyle.TOUCH_SIZE
	_project_button.focus_mode = Control.FOCUS_NONE
	_project_button.icon = MobileStyle.icon("chevron_down")
	_project_button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_project_button.expand_icon = true
	_project_button.add_theme_constant_override("icon_max_width", 18)
	_project_button.add_theme_font_size_override("font_size", 17)
	_project_button.pressed.connect(open_projects)
	hbox.add_child(_project_button)

	_undo_button = MobileStyle.make_icon_button("undo")
	_undo_button.pressed.connect(_top_menu.edit_menu_id_pressed.bind(Global.EditMenu.UNDO))
	hbox.add_child(_undo_button)
	_redo_button = MobileStyle.make_icon_button("redo")
	_redo_button.pressed.connect(_top_menu.edit_menu_id_pressed.bind(Global.EditMenu.REDO))
	hbox.add_child(_redo_button)
	_layers_button = MobileStyle.make_icon_button("layers")
	_layers_button.pressed.connect(open_layers)
	hbox.add_child(_layers_button)

	_menu_and_ui.add_child(_top_bar)
	_menu_and_ui.move_child(_top_bar, 0)
	_style_bars()


func _build_bottom_bar() -> void:
	_bottom_bar = PanelContainer.new()
	_bottom_bar.name = "MobileBottomBar"
	_bottom_bar.theme = _touch_theme
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	_bottom_bar.add_child(hbox)

	_color_button = Button.new()
	_color_button.custom_minimum_size = Vector2(60, MobileStyle.BAR_HEIGHT - 8)
	_color_button.focus_mode = Control.FOCUS_NONE
	_color_button.pressed.connect(open_colors)
	_color_swatch = Panel.new()
	_color_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_color_swatch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_color_swatch.offset_left = 8
	_color_swatch.offset_right = -8
	_color_swatch.offset_top = 6
	_color_swatch.offset_bottom = -6
	_color_button.add_child(_color_swatch)
	hbox.add_child(_color_button)

	for tool_name in QUICK_TOOLS:
		var button := _make_tool_button(tool_name, 32)
		button.pressed.connect(_select_tool.bind(tool_name))
		hbox.add_child(button)
		_quick_buttons[tool_name] = button

	_more_button = MobileStyle.make_icon_button("grid")
	_more_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_more_button.custom_minimum_size = Vector2(0, MobileStyle.BAR_HEIGHT - 8)
	_more_button.pressed.connect(open_tools)
	hbox.add_child(_more_button)

	_options_button = MobileStyle.make_icon_button("sliders")
	_options_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_options_button.custom_minimum_size = Vector2(0, MobileStyle.BAR_HEIGHT - 8)
	_options_button.pressed.connect(open_options)
	hbox.add_child(_options_button)

	_menu_and_ui.add_child(_bottom_bar)
	_style_bars()


func _style_bars() -> void:
	if is_instance_valid(_top_bar):
		var top_style := MobileStyle.flat(MobileStyle.base_color(), 0, 6, 4)
		top_style.border_width_bottom = 1
		top_style.border_color = MobileStyle.surface(0.16)
		_top_bar.add_theme_stylebox_override("panel", top_style)
		for button in [_project_button, _undo_button, _redo_button, _layers_button]:
			MobileStyle.style_button(button, false, 12, 12 if button == _project_button else 0)
			if button == _project_button:
				button.add_theme_color_override("font_color", MobileStyle.icon_color())
	if is_instance_valid(_bottom_bar):
		var bottom_style := MobileStyle.flat(MobileStyle.base_color(), 0, 6, 4)
		bottom_style.border_width_top = 1
		bottom_style.border_color = MobileStyle.surface(0.16)
		_bottom_bar.add_theme_stylebox_override("panel", bottom_style)
		MobileStyle.style_button(_color_button, false, 12)
		MobileStyle.style_button(_options_button, false, 12)
		_update_tool_buttons()


func _make_tool_button(tool_name: String, icon_size: int) -> Button:
	var tool_data: Tools.Tool = Tools.tools[tool_name]
	var button := Button.new()
	button.icon = tool_data.icon
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	button.add_theme_constant_override("icon_max_width", icon_size)
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, MobileStyle.BAR_HEIGHT - 8)
	button.tooltip_text = tool_data.generate_hint_tooltip()
	MobileStyle.style_button(button)
	return button


func _connect_signals() -> void:
	Tools.tool_changed.connect(_on_tool_changed)
	Tools.color_changed.connect(_on_color_changed)
	Global.project_switched.connect(_refresh_project)
	Global.cel_switched.connect(_refresh_project)
	Themes.theme_switched.connect(_on_theme_switched)
	_main.get_window().size_changed.connect(_on_window_resized)


#endregion


#region Opening sheets
func open_menu() -> void:
	_menu.show_root()
	_open_sheet(_menu_sheet)


func open_projects() -> void:
	_menu.show_projects()
	_open_sheet(_menu_sheet)


func open_colors() -> void:
	_open_sheet(_color_sheet)


func open_options() -> void:
	_open_sheet(_options_sheet)


func open_layers() -> void:
	_open_sheet(_layers_sheet)


func open_tools() -> void:
	_open_sheet(_tools_sheet)


## Opens one of the panels listed in [constant PANEL_NAMES].
func open_panel(panel_name: String) -> void:
	var panel := _panels.get(panel_name) as Control
	if panel == null:
		return
	_panel_sheet.title = panel_name
	_panel_sheet.set_content(panel, 8, _holder, true)
	_open_sheet(_panel_sheet)


func close_all_sheets() -> void:
	for sheet in _sheets:
		sheet.close()


func _open_sheet(sheet: MobileSheet) -> void:
	for other in _sheets:
		if other != sheet and other.is_open:
			other.close()
	sheet.open()


func _on_sheet_opened(sheet: MobileSheet) -> void:
	if sheet == _options_sheet or sheet == _color_sheet:
		_update_color_swatch()


func _show_color_tab(index: int) -> void:
	var color_panels: Array[Control] = [_panels["Color Picker"], _panels["Palettes"]]
	for i in color_panels.size():
		color_panels[i].visible = i == index
		_color_tabs[i].button_pressed = i == index
		MobileStyle.style_button(_color_tabs[i], i == index, 10, 12, true)


func _populate_tools_grid() -> void:
	for child in _tools_grid.get_children():
		_tools_grid.remove_child(child)
		child.queue_free()
	var left_slot := Tools.get_tool(MOUSE_BUTTON_LEFT)
	var current := ""
	if left_slot != null and left_slot.tool_node != null:
		current = String(left_slot.tool_node.name)
	for tool_name in Tools.tools:
		var tool_data: Tools.Tool = Tools.tools[tool_name]
		if is_instance_valid(tool_data.button_node) and not tool_data.button_node.visible:
			continue
		var button := Button.new()
		button.text = tr(tool_data.display_name)
		button.icon = tool_data.icon
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.add_theme_constant_override("icon_max_width", 32)
		button.add_theme_constant_override("h_separation", 0)
		button.add_theme_font_size_override("font_size", 12)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.clip_text = true
		button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 84)
		MobileStyle.style_button(button, tool_name == current, 12, 4)
		button.pressed.connect(
			func() -> void:
				_select_tool(tool_name)
				_tools_sheet.close()
		)
		_tools_grid.add_child(button)


#endregion


#region State
func _select_tool(tool_name: String) -> void:
	Tools.assign_tool(tool_name, MOUSE_BUTTON_LEFT)
	Tools.prev_tool_names[MOUSE_BUTTON_LEFT] = ""
	_update_tool_buttons()


func _on_tool_changed(_tool_name: String, _button: int) -> void:
	_update_tool_buttons()


func _on_color_changed(_color_info: Dictionary, button: int) -> void:
	if button == MOUSE_BUTTON_LEFT:
		_update_color_swatch()


func _update_tool_buttons() -> void:
	if _quick_buttons.is_empty():
		return
	var left_slot := Tools.get_tool(MOUSE_BUTTON_LEFT)
	var current := ""
	if left_slot != null and left_slot.tool_node != null:
		current = String(left_slot.tool_node.name)
	for tool_name in _quick_buttons:
		var button := _quick_buttons[tool_name]
		MobileStyle.style_button(button, tool_name == current)
		var tool_data: Tools.Tool = Tools.tools.get(tool_name)
		button.visible = (
			tool_data == null
			or not is_instance_valid(tool_data.button_node)
			or tool_data.button_node.visible
		)
	# The "all tools" button shows the current tool if it has no button of its own.
	if current != "" and not current in QUICK_TOOLS and current in Tools.tools:
		var tool_data: Tools.Tool = Tools.tools[current]
		_more_button.icon = tool_data.icon
		_more_button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_more_button.add_theme_constant_override("icon_max_width", 32)
		MobileStyle.style_button(_more_button, true)
	else:
		_more_button.icon = MobileStyle.icon("grid")
		_more_button.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE
		_more_button.add_theme_constant_override("icon_max_width", 26)
		MobileStyle.style_button(_more_button, false)


func _update_color_swatch() -> void:
	if not is_instance_valid(_color_swatch):
		return
	var color := Tools.get_assigned_color(MOUSE_BUTTON_LEFT)
	var style := MobileStyle.flat(color, 10)
	style.set_border_width_all(2)
	style.border_color = MobileStyle.icon_color()
	_color_swatch.add_theme_stylebox_override("panel", style)


func _refresh_all() -> void:
	_update_color_swatch()
	_update_tool_buttons()
	_refresh_project()


func _refresh_project() -> void:
	if not is_instance_valid(_project_button) or Global.current_project == null:
		return
	var project := Global.current_project
	_project_button.text = project.name + ("  *" if project.has_changed else "")
	_poll_state()


func _poll_state() -> void:
	var project := Global.current_project
	if project == null or not is_instance_valid(_undo_button):
		return
	var title := project.name + ("  *" if project.has_changed else "")
	if _project_button.text != title:
		_project_button.text = title


func _is_panel_relevant(panel_name: String) -> bool:
	var cel := Global.current_project.get_current_cel()
	if panel_name == "Tiles":
		return cel is CelTileMap
	if panel_name == "3D Object Tree":
		return cel is Cel3D
	return _panels.has(panel_name)


func _on_menu_page_changed(page_title: String, can_go_back: bool) -> void:
	_menu_sheet.title = page_title
	_menu_sheet.set_back_visible(can_go_back)


func _on_modifier_toggled(toggled_on: bool, keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = toggled_on
	Input.parse_input_event(event)


func _on_theme_switched() -> void:
	_touch_theme = MobileStyle.make_touch_theme(_main.theme)
	var dialogs := _main.get_node_or_null("Dialogs") as Control
	if dialogs:
		dialogs.theme = _touch_theme
	_sheet_layer.theme = _touch_theme
	_top_bar.theme = _touch_theme
	_bottom_bar.theme = _touch_theme
	_style_bars()
	_update_color_swatch()
	_show_color_tab(0 if _color_tabs[0].button_pressed else 1)


func _on_window_resized() -> void:
	_sheet_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _on_ui_scale_change_requested(step: int) -> void:
	var factor: float = Global.config_cache.get_value("preferences", "mobile_ui_scale", 1.0)
	var index := 0
	var best := INF
	for i in SCALE_FACTORS.size():
		if absf(SCALE_FACTORS[i] - factor) < best:
			best = absf(SCALE_FACTORS[i] - factor)
			index = i
	index = clampi(index + step, 0, SCALE_FACTORS.size() - 1)
	Global.config_cache.set_value("preferences", "mobile_ui_scale", SCALE_FACTORS[index])
	var new_scale := compute_display_scale()
	# Keep Pixelorama's own "interface scale" preference in sync, since it takes priority.
	Global.config_cache.set_value("preferences", "shrink", new_scale)
	Global.config_cache.save(Global.CONFIG_PATH)
	Global.shrink = new_scale
	Global.auto_content_scale_factor = new_scale
	_main.set_display_scale()
	_main.set_mobile_fullscreen_safe_area()
	_menu.refresh()


func _on_classic_layout_requested() -> void:
	request_layout_switch(self, false)

#endregion
