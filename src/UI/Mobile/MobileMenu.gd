class_name MobileMenu
extends VBoxContainer
## Presents Pixelorama's top menu as large, touch friendly lists.
## It reads the existing PopupMenus, so every feature (and every entry added by extensions)
## is kept, and activating an item runs exactly the same code as on desktop.

signal page_changed(title: String, can_go_back: bool)
## Emitted when an action was chosen and the menu should close.
signal close_requested
signal panel_requested(panel_name: String)
signal ui_scale_change_requested(step: int)
signal classic_layout_requested

## The TopMenuContainer node, which owns the menu PopupMenus.
var top_menu: Control
## The names of the panels that can be opened from the "Panels" page.
var panel_names: Array[String] = []
## Used to find out if a panel is relevant right now (for example, the Tiles panel).
var panel_available := func(_panel_name: String) -> bool: return true

var _scroll := ScrollContainer.new()
var _list := VBoxContainer.new()
var _stack: Array[Dictionary] = []


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	_scroll.add_child(_list)


func show_root() -> void:
	_stack.clear()
	_go("Menu", _build_root)


func show_page(title: String, builder: Callable) -> void:
	_stack.clear()
	_go(title, builder)


func go_back() -> void:
	if _stack.size() > 1:
		_stack.pop_back()
		_render()


func can_go_back() -> bool:
	return _stack.size() > 1


func _go(title: String, builder: Callable) -> void:
	_stack.append({"title": title, "build": builder})
	_render()
	_scroll.scroll_vertical = 0


func _render() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var page: Dictionary = _stack.back()
	(page["build"] as Callable).call()
	page_changed.emit(page["title"], _stack.size() > 1)


## Rebuilds the current page, keeping the scroll position.
func refresh() -> void:
	var scroll := _scroll.scroll_vertical
	_render()
	await get_tree().process_frame
	_scroll.scroll_vertical = scroll


func _build_root() -> void:
	var entries: Array[Dictionary] = [
		{"text": "File", "menu": top_menu.file_menu},
		{"text": "Edit", "menu": top_menu.edit_menu},
		{"text": "Select", "menu": top_menu.select_menu},
		{"text": "Project", "menu": top_menu.project_menu},
		{"text": "Effects", "menu": top_menu.effects_menu},
		{"text": "View", "menu": top_menu.view_menu},
	]
	for entry in entries:
		var popup: PopupMenu = entry["menu"]
		var row := _make_row(entry["text"])
		_set_trailing(row, "chevron_right")
		row.pressed.connect(_go.bind(entry["text"], _build_popup_page.bind(popup)))
		_list.add_child(row)
	var panels_row := _make_row("Panels")
	_set_trailing(panels_row, "chevron_right")
	panels_row.pressed.connect(_go.bind("Panels", _build_panels_page))
	_list.add_child(panels_row)
	var help_row := _make_row("Help")
	_set_trailing(help_row, "chevron_right")
	help_row.pressed.connect(_go.bind("Help", _build_popup_page.bind(top_menu.help_menu)))
	_list.add_child(help_row)
	_list.add_child(_make_separator())
	var layout_row := _make_row("Touch layout")
	_set_trailing(layout_row, "chevron_right")
	layout_row.pressed.connect(_go.bind("Touch layout", _build_layout_page))
	_list.add_child(layout_row)


func _build_panels_page() -> void:
	for panel_name in panel_names:
		if not panel_available.call(panel_name):
			continue
		var row := _make_row(panel_name)
		row.pressed.connect(func() -> void: panel_requested.emit(panel_name))
		_list.add_child(row)


func _build_layout_page() -> void:
	var scale_row := HBoxContainer.new()
	scale_row.custom_minimum_size.y = 56
	var label := Label.new()
	label.text = tr("Interface size")
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(label)
	scale_row.add_child(margin)
	var smaller := MobileStyle.make_icon_button("minus")
	smaller.pressed.connect(func() -> void: ui_scale_change_requested.emit(-1))
	var value_label := Label.new()
	value_label.text = "%d%%" % roundi(Global.shrink / MobileUI.get_base_display_scale() * 100.0)
	value_label.custom_minimum_size.x = 64
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var bigger := MobileStyle.make_icon_button("plus")
	bigger.pressed.connect(func() -> void: ui_scale_change_requested.emit(1))
	scale_row.add_child(smaller)
	scale_row.add_child(value_label)
	scale_row.add_child(bigger)
	_list.add_child(scale_row)
	_list.add_child(_make_separator())
	var classic_row := _make_row("Use the classic desktop layout")
	classic_row.pressed.connect(classic_layout_requested.emit)
	_list.add_child(classic_row)


## Shows the list of open projects, to switch between them.
func show_projects() -> void:
	show_page("Projects", _build_projects_page)


func _build_projects_page() -> void:
	for i in Global.projects.size():
		var project := Global.projects[i]
		var text := project.name + ("  *" if project.has_changed else "")
		var row := _make_row(text)
		var is_current := i == Global.current_project_index
		_set_trailing(row, "check" if is_current else "")
		row.pressed.connect(
			func() -> void:
				Global.tabs.current_tab = i
				close_requested.emit()
		)
		_list.add_child(row)
	_list.add_child(_make_separator())
	var new_row := _make_row("New...")
	new_row.pressed.connect(
		func() -> void:
			close_requested.emit()
			top_menu.file_menu.activate_item.call_deferred(Global.FileMenu.NEW)
	)
	_list.add_child(new_row)
	if Global.projects.size() > 1:
		var close_row := _make_row("Close project")
		close_row.pressed.connect(
			func() -> void:
				close_requested.emit()
				Global.tabs.tab_close_pressed.emit(Global.current_project_index)
		)
		_list.add_child(close_row)


func _build_popup_page(popup: PopupMenu) -> void:
	for i in popup.item_count:
		if popup.is_item_separator(i):
			_list.add_child(_make_separator())
			continue
		var text := popup.get_item_text(i)
		var row := _make_row(text, popup.get_item_icon(i))
		row.disabled = popup.is_item_disabled(i)
		var submenu: PopupMenu = popup.get_item_submenu_node(i)
		if submenu != null:
			_set_trailing(row, "chevron_right")
			row.pressed.connect(_go.bind(text, _build_popup_page.bind(submenu)))
		elif popup.is_item_checkable(i):
			_set_trailing(row, "check" if popup.is_item_checked(i) else "")
			row.pressed.connect(_on_checkable_item_pressed.bind(popup, i))
		else:
			row.pressed.connect(_on_item_pressed.bind(popup, i))
		_list.add_child(row)
	if popup.item_count == 0:
		var label := Label.new()
		label.text = tr("Nothing here yet")
		label.modulate.a = 0.6
		_list.add_child(label)


func _on_item_pressed(popup: PopupMenu, index: int) -> void:
	close_requested.emit()
	# Wait a moment, so that the dialog that this item may open appears over a closing menu.
	popup.activate_item.call_deferred(index)


func _on_checkable_item_pressed(popup: PopupMenu, index: int) -> void:
	popup.activate_item(index)
	refresh()


func _make_row(text: String, leading_icon: Texture2D = null) -> Button:
	var row := Button.new()
	row.text = tr(text)
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.focus_mode = Control.FOCUS_NONE
	row.custom_minimum_size.y = 52
	row.clip_text = true
	row.icon = leading_icon
	row.expand_icon = leading_icon != null
	row.add_theme_constant_override("icon_max_width", 24)
	row.add_theme_constant_override("h_separation", 12)
	row.add_theme_font_size_override("font_size", 17)
	MobileStyle.style_button(row, false, 10, 16)
	# Make room for the trailing icon.
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := row.get_theme_stylebox(state) as StyleBoxFlat
		if sb != null:
			sb.content_margin_right = 48
	return row


func _make_separator() -> Control:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 12)
	return sep


func _set_trailing(row: Button, icon_name: String) -> void:
	if icon_name.is_empty():
		return
	var icon := TextureRect.new()
	icon.texture = MobileStyle.icon(icon_name)
	icon.modulate = MobileStyle.icon_color()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	icon.offset_left = -40
	icon.offset_right = -14
	icon.offset_top = -13
	icon.offset_bottom = 13
	row.add_child(icon)
