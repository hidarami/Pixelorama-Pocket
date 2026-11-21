class_name MobileSheet
extends Control
## A panel that slides up from the bottom of the screen and floats over the canvas.
## Any Control can be put inside it with [method set_content].

signal opened
signal closed
## Emitted when the back button of the header is pressed.
signal back_pressed

## The text shown in the header.
var title := "":
	set(value):
		title = value
		if is_instance_valid(_title_label):
			_title_label.text = tr(title)
## The fraction of the available height that the sheet takes up when open.
var height_ratio := 0.6:
	set(value):
		height_ratio = value
		_layout_panel(1.0 if is_open else 0.0)
var is_open := false
var content_margin := 8:
	set(value):
		content_margin = value
		if is_instance_valid(_body):
			for side in ["left", "right", "bottom"]:
				_body.add_theme_constant_override("margin_" + side, content_margin)
			_body.add_theme_constant_override("margin_top", 0)

var _scrim := ColorRect.new()
var _panel := PanelContainer.new()
var _title_label := Label.new()
var _back_button: Button
var _close_button: Button
var _header := HBoxContainer.new()
var _body := MarginContainer.new()
var _wrapper: ScrollContainer
var _header_extra := HBoxContainer.new()
var _tween: Tween
var _drag_start := Vector2.ZERO
var _dragging := false
var _scrim_pressed := false
var _bottom_inset := 0.0


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	_scrim.color = Color(0, 0, 0, 0.0)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.gui_input.connect(_on_scrim_gui_input)
	add_child(_scrim)

	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.clip_contents = true
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_apply_panel_style()
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	_panel.add_child(vbox)

	# Drag handle + header
	var handle_holder := CenterContainer.new()
	handle_holder.custom_minimum_size.y = 14
	handle_holder.mouse_filter = Control.MOUSE_FILTER_PASS
	var handle := Panel.new()
	handle.custom_minimum_size = Vector2(40, 4)
	handle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	handle.add_theme_stylebox_override("panel", MobileStyle.flat(Color(0.5, 0.5, 0.55, 0.7), 2))
	handle_holder.add_child(handle)
	handle_holder.gui_input.connect(_on_header_gui_input)
	vbox.add_child(handle_holder)

	_header.mouse_filter = Control.MOUSE_FILTER_PASS
	_header.custom_minimum_size.y = MobileStyle.TOUCH_SIZE
	_header.gui_input.connect(_on_header_gui_input)
	vbox.add_child(_header)

	_back_button = MobileStyle.make_icon_button("chevron_left")
	_back_button.visible = false
	_back_button.pressed.connect(func() -> void: back_pressed.emit())
	_header.add_child(_back_button)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	_header.add_child(margin)
	_title_label.text = tr(title)
	_title_label.add_theme_font_size_override("font_size", 18)
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.clip_text = true
	_title_label.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_child(_title_label)

	_header_extra.mouse_filter = Control.MOUSE_FILTER_PASS
	_header.add_child(_header_extra)

	_close_button = MobileStyle.make_icon_button("close")
	_close_button.pressed.connect(close)
	_header.add_child(_close_button)

	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.clip_contents = true
	content_margin = content_margin
	vbox.add_child(_body)

	resized.connect(func() -> void: _layout_panel(1.0 if is_open else 0.0))
	Themes.theme_switched.connect(_apply_panel_style)
	_layout_panel(0.0)


func _apply_panel_style() -> void:
	var sb := MobileStyle.flat(MobileStyle.base_color(), 18)
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	sb.border_width_top = 1
	sb.border_color = MobileStyle.surface(0.18)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 14
	_panel.add_theme_stylebox_override("panel", sb)


## Sets the safe area inset at the bottom of the screen, so the content isn't covered.
func set_bottom_inset(inset: float) -> void:
	_bottom_inset = inset
	_body.add_theme_constant_override("margin_bottom", content_margin + int(inset))


## Puts [param control] inside the sheet, replacing any previous content.
## The previous content is moved to [param release_to] if given, otherwise it is just removed.
## If [param h_scroll] is [code]true[/code], content that is wider than the screen can be
## scrolled sideways, instead of making the whole sheet wider than the screen.
func set_content(control: Control, margin := 8, release_to: Node = null, h_scroll := false) -> void:
	# Move the new content out of the way first, in case it already is in this sheet.
	if control.get_parent() != null and control.get_parent() != _body:
		control.reparent(_body, false)
	for holder: Node in [_body, _wrapper]:
		if not is_instance_valid(holder):
			continue
		for child in holder.get_children():
			if child == control or child == _wrapper:
				continue
			if release_to != null:
				child.reparent(release_to, false)
			else:
				holder.remove_child(child)
	if is_instance_valid(_wrapper):
		if control.get_parent() == _wrapper:
			control.reparent(_body, false)
		_body.remove_child(_wrapper)
		_wrapper.queue_free()
		_wrapper = null
	content_margin = margin
	set_bottom_inset(_bottom_inset)
	var content_parent: Node = _body
	if h_scroll:
		_wrapper = ScrollContainer.new()
		_wrapper.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		_wrapper.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_body.add_child(_wrapper)
		content_parent = _wrapper
	if control.get_parent() == null:
		content_parent.add_child(control)
	elif control.get_parent() != content_parent:
		control.reparent(content_parent, false)
	control.visible = true
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_vertical = Control.SIZE_EXPAND_FILL


## Adds a control (such as a button) to the right side of the header.
func add_header_control(control: Control) -> void:
	_header_extra.add_child(control)


func set_back_visible(back_visible: bool) -> void:
	_back_button.visible = back_visible


func open() -> void:
	if is_open:
		return
	is_open = true
	visible = true
	_kill_tween()
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.set_parallel(true)
	_tween.tween_method(_layout_panel, 0.0, 1.0, 0.2)
	_tween.tween_property(_scrim, "color:a", 0.45, 0.2)
	opened.emit()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_kill_tween()
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.set_parallel(true)
	_tween.tween_method(_layout_panel, 1.0, 0.0, 0.16)
	_tween.tween_property(_scrim, "color:a", 0.0, 0.16)
	_tween.chain().tween_callback(func() -> void: visible = is_open)
	closed.emit()


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()


## [param amount] is 0 when the sheet is hidden below the screen and 1 when fully open.
func _layout_panel(amount: float) -> void:
	if not is_instance_valid(_panel):
		return
	var height := roundf(size.y * height_ratio)
	_panel.offset_left = 0
	_panel.offset_right = 0
	_panel.offset_top = -height * amount
	_panel.offset_bottom = height * (1.0 - amount)


func _on_scrim_gui_input(event: InputEvent) -> void:
	# The sheet closes when the pointer is released, not when it is pressed. That way a drag that
	# starts on the dimmed area is swallowed here and can't turn into a stroke on the canvas.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_scrim_pressed = true
		elif _scrim_pressed:
			_scrim_pressed = false
			close()
	accept_event()


func _on_header_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_start = event.global_position
		else:
			if _dragging and event.global_position.y - _drag_start.y > 48.0:
				close()
			_dragging = false
