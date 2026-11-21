class_name MobileStyle
extends RefCounted
## Helpers that give the mobile UI its look and touch-friendly sizes.
## The colors are derived from the currently selected Pixelorama theme.

const ICON_DIR := "res://assets/graphics/mobile/"
## The smallest comfortable touch target, in UI units (about 48dp on a phone).
const TOUCH_SIZE := 48.0
const BAR_HEIGHT := 56.0
const CORNER_RADIUS := 14


static func icon(icon_name: String) -> Texture2D:
	return load(ICON_DIR + icon_name + ".svg") as Texture2D


static func base_color() -> Color:
	var idx := Global.theme_preset_index
	if idx >= 0 and idx < Themes.themes.size():
		return Themes.themes[idx].get_base_color()
	return Color("2b2b30")


static func accent_color() -> Color:
	var idx := Global.theme_preset_index
	if idx >= 0 and idx < Themes.themes.size():
		return Themes.themes[idx].get_accent_color()
	return Color("0086cf")


static func is_light_theme() -> bool:
	return base_color().get_luminance() > 0.5


## A color slightly lighter (or darker, on light themes) than the base color.
static func surface(amount := 0.06) -> Color:
	var base := base_color()
	return base.darkened(amount) if is_light_theme() else base.lightened(amount)


static func icon_color() -> Color:
	return Color("2c2c34") if is_light_theme() else Color("e6e6ee")


static func flat(
	color: Color, radius := CORNER_RADIUS, margin_h := 0, margin_v := 0, border := 0
) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin_h
	sb.content_margin_right = margin_h
	sb.content_margin_top = margin_v
	sb.content_margin_bottom = margin_v
	if border > 0:
		sb.set_border_width_all(border)
		sb.border_color = accent_color()
	return sb


## The color of text and icons that are drawn over the accent color.
static func on_accent_color() -> Color:
	return Color(0.07, 0.07, 0.09) if accent_color().get_luminance() > 0.45 else Color.WHITE


## Makes [param button] look like a flat touch friendly button.
## [param selected] gives it the accent color. [param filled] gives it a visible background
## even when it isn't selected or pressed.
static func style_button(
	button: Button, selected := false, radius := 12, margin_h := 0, filled := false
) -> void:
	var accent := accent_color()
	var rest_color := surface(0.1) if filled else Color(0, 0, 0, 0)
	var normal := flat(accent if selected else rest_color, radius, margin_h)
	var hover := flat(accent if selected else surface(0.16 if filled else 0.1), radius, margin_h)
	var pressed := flat(accent.lightened(0.1) if selected else accent, radius, margin_h)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	var focus := StyleBoxEmpty.new()
	focus.content_margin_left = margin_h
	focus.content_margin_right = margin_h
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_stylebox_override("disabled", flat(rest_color, radius, margin_h))
	var on_accent := on_accent_color()
	var rest := icon_color() if is_light_theme() else Color.WHITE
	var main_color := on_accent if selected else rest
	for state in ["icon_normal_color", "icon_hover_color", "icon_focus_color"]:
		button.add_theme_color_override(state, main_color)
	for state in ["icon_pressed_color", "icon_hover_pressed_color"]:
		button.add_theme_color_override(state, on_accent)
	button.add_theme_color_override("icon_disabled_color", Color(rest, 0.35))
	# Text colors. They follow the theme, except where they would sit on the accent color.
	var font_states := ["font_color", "font_hover_color", "font_focus_color"]
	for state in font_states:
		if selected:
			button.add_theme_color_override(state, on_accent)
		else:
			button.remove_theme_color_override(state)
	for state in ["font_pressed_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(state, on_accent)


static func make_icon_button(icon_name: String, size := TOUCH_SIZE) -> Button:
	var button := Button.new()
	button.icon = icon(icon_name)
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	button.custom_minimum_size = Vector2(size, size)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_constant_override("icon_max_width", int(size * 0.5))
	style_button(button)
	return button


## Returns a small Theme that makes common controls larger and easier to tap.
## It only overrides sizes, so the colors still follow the selected Pixelorama theme.
static func make_touch_theme(source: Theme) -> Theme:
	var theme := Theme.new()
	var pad_v := 9
	var pad_h := 12
	for type_name in ["Button", "OptionButton", "MenuButton"]:
		for state in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
			var sb := _get_stylebox(source, state, type_name)
			if sb == null:
				continue
			sb = sb.duplicate()
			sb.content_margin_top = maxf(sb.content_margin_top, pad_v)
			sb.content_margin_bottom = maxf(sb.content_margin_bottom, pad_v)
			sb.content_margin_left = maxf(sb.content_margin_left, pad_h)
			sb.content_margin_right = maxf(sb.content_margin_right, pad_h)
			theme.set_stylebox(state, type_name, sb)
	for type_name in ["CheckBox", "CheckButton"]:
		for state in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
			var sb := _get_stylebox(source, state, type_name)
			if sb == null:
				continue
			sb = sb.duplicate()
			sb.content_margin_top = maxf(sb.content_margin_top, pad_v)
			sb.content_margin_bottom = maxf(sb.content_margin_bottom, pad_v)
			theme.set_stylebox(state, type_name, sb)
	for state in ["normal", "focus", "read_only"]:
		var sb := _get_stylebox(source, state, "LineEdit")
		if sb == null:
			continue
		sb = sb.duplicate()
		sb.content_margin_top = maxf(sb.content_margin_top, pad_v)
		sb.content_margin_bottom = maxf(sb.content_margin_bottom, pad_v)
		theme.set_stylebox(state, "LineEdit", sb)
	return theme


static func _get_stylebox(source: Theme, state: String, type_name: String) -> StyleBox:
	if source != null and source.has_stylebox(state, type_name):
		return source.get_stylebox(state, type_name)
	return ThemeDB.get_default_theme().get_stylebox(state, type_name)
