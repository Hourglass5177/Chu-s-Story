class_name MainUI
extends RefCounted

## September artist delivery. Scoped to the board UI, never the minigame host.
const ROOT := "res://arts/ui-main-v1/"
const FONT := preload("res://arts/ui-main-v1/fonts/SourceHanSansSC-Regular.otf")
const TITLE_FONT := preload("res://arts/ui-main-v1/fonts/SourceHanSerifSC-SemiBold.otf")
const PIXEL_FONT := preload("res://InheritanceTasks/Art/Pixel/v2/fonts/fusion-pixel-12px-proportional-zh_hans.ttf")
const INK := Color("4f4138")
static var _textures: Dictionary = {}
static var _styles: Dictionary = {}
static var _theme: Theme

static func texture(key: String) -> Texture2D:
	if not _textures.has(key):
		_textures[key] = load(ROOT + key + ".png")
	return _textures[key] as Texture2D

static func box(key: String = "panel", margin: float = 36.0) -> StyleBoxTexture:
	var cache_key := key + str(margin)
	if _styles.has(cache_key): return _styles[cache_key]
	var style := StyleBoxTexture.new()
	style.texture = texture(key)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		# These are complete illustrated frames, not arbitrary 17%-border tiles.
		# Keep the complete ornament; the caller supplies a matching aspect ratio.
		style.set_texture_margin(side, 0)
		style.set_content_margin(side, margin)
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	_styles[cache_key] = style
	return style

static func theme() -> Theme:
	if _theme != null: return _theme
	_theme = Theme.new()
	_theme.default_font = FONT
	_theme.default_font_size = 40
	for kind in ["Label", "Button", "LineEdit", "RichTextLabel"]:
		_theme.set_color("font_color", kind, INK)
		_theme.set_constant("outline_size", kind, 0)
	for state in ["normal", "hover", "pressed", "disabled"]:
		_theme.set_stylebox(state, "Button", box("primary_" + state, 16))
		_theme.set_color("font_" + state + "_color", "Button", INK)
	_theme.set_color("font_disabled_color", "Button", Color("807365"))
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = Color("387c88")
	focus.set_border_width_all(4)
	focus.set_corner_radius_all(10)
	_theme.set_stylebox("focus", "Button", focus)
	_theme.set_stylebox("panel", "Panel", box())
	_theme.set_stylebox("panel", "PanelContainer", box())
	return _theme

static func label(control: Control, size: int = 40, heading: bool = false) -> void:
	control.add_theme_font_override("font", TITLE_FONT if heading else FONT)
	control.add_theme_font_size_override("font_size", size)
	control.add_theme_color_override("font_color", INK)
	control.add_theme_constant_override("outline_size", 0)
	control.modulate = Color.WHITE

static func button(control: Button, kind: String = "primary") -> void:
	control.theme = theme()
	label(control)
	control.custom_minimum_size.y = maxf(104, control.custom_minimum_size.y)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var asset: String = kind + "_" + state
		if kind == "danger" and state == "disabled": asset = "secondary_disabled"
		control.add_theme_stylebox_override(state, box(asset, 16))
		control.add_theme_color_override("font_" + state + "_color", INK)
	control.add_theme_stylebox_override("focus", theme().get_stylebox("focus", "Button"))
	control.add_theme_color_override("font_disabled_color", Color("807365"))
	control.add_theme_color_override("font_focus_color", INK)
	control.focus_mode = Control.FOCUS_ALL
	control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

static func pixel_label(control: Control, size: int = 48) -> void:
	# Reuse the minigame font for compact numeric/status information, not long prose.
	label(control, size)
	control.add_theme_font_override("font", PIXEL_FONT)

static func surface(parent: Node, key: String, node_name: String = "ArtistSurface") -> TextureRect:
	var result := TextureRect.new()
	result.name = node_name
	result.texture = texture(key)
	result.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	parent.move_child(result, 0)
	fill(result)
	return result

static func compact_button(control: Button, selected: bool = false) -> void:
	# Small square controls and filter chips cannot stretch a long ornamental button.
	button(control)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("e9b567") if selected else Color("fff2d5")
		if state == "hover": style.bg_color = Color("f4ce8c")
		if state == "pressed": style.bg_color = Color("d99a50")
		if state == "disabled": style.bg_color = Color("e2d9c8")
		style.border_color = Color("a9794e")
		style.set_border_width_all(2)
		style.set_corner_radius_all(8)
		style.content_margin_left = 18
		style.content_margin_right = 18
		style.content_margin_top = 12
		style.content_margin_bottom = 12
		control.add_theme_stylebox_override(state, style)

static func guide_button(control: Button) -> void:
	control.icon = texture("guide")
	control.expand_icon = true
	control.add_theme_constant_override("icon_max_width", 86)
	control.add_theme_constant_override("h_separation", 12)
	label(control, 40)
	for state in ["normal", "hover", "pressed", "disabled"]:
		control.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	control.custom_minimum_size = Vector2(200, 108)

static func apply(root: Node) -> void:
	if root is Control:
		root.theme = theme()
	if root is Button: button(root)
	elif root is Label: label(root, clampi(root.get_theme_font_size("font_size"), 36, 64))
	elif root is RichTextLabel:
		root.add_theme_font_override("normal_font", FONT)
		root.add_theme_font_size_override("normal_font_size", 40)
		root.add_theme_color_override("default_color", INK)
	for child in root.get_children(): apply(child)

static func typography(root: Node) -> void:
	# Preserve state colours and control geometry on the existing setup/roster pages.
	if root is Control:
		root.add_theme_font_override("font", FONT)
		root.add_theme_constant_override("outline_size", 0)
		if root is Label or root is Button or root is LineEdit:
			root.add_theme_font_size_override("font_size", maxi(36, root.get_theme_font_size("font_size")))
	for child in root.get_children(): typography(child)

static func rect(control: Control, area: Rect2) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	control.position = area.position
	control.size = area.size

static func fill(control: Control, inset: float = 0) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control.offset_left = inset
	control.offset_top = inset
	control.offset_right = -inset
	control.offset_bottom = -inset

static func backdrop(parent: Node, key: String) -> NinePatchRect:
	var panel := NinePatchRect.new()
	panel.name = "ArtistBackground"
	panel.texture = texture(key)
	panel.patch_margin_left = 80
	panel.patch_margin_right = 80
	panel.patch_margin_top = 80
	panel.patch_margin_bottom = 80
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	parent.move_child(panel, 0)
	fill(panel)
	return panel

static func icon(control: TextureButton, key: String) -> void:
	control.texture_normal = texture(key)
	control.texture_hover = null
	control.texture_pressed = null
	control.texture_click_mask = null
	control.ignore_texture_size = true
	control.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	control.focus_mode = Control.FOCUS_ALL
	control.add_theme_stylebox_override("focus", theme().get_stylebox("focus", "Button"))
	if not control.has_meta("board_icon_feedback"):
		control.set_meta("board_icon_feedback", true)
		control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		control.mouse_entered.connect(func(): control.self_modulate = Color(1.15, 1.12, 1.05))
		control.mouse_exited.connect(func(): control.self_modulate = Color.WHITE)
		control.button_down.connect(func(): control.self_modulate = Color(0.8, 0.76, 0.68))
		control.button_up.connect(func(): control.self_modulate = Color.WHITE)
		var ring := Panel.new()
		ring.name = "KeyboardFocus"
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.add_theme_stylebox_override("panel", theme().get_stylebox("focus", "Button"))
		control.add_child(ring)
		fill(ring)
		ring.hide()
		control.focus_entered.connect(ring.show)
		control.focus_exited.connect(ring.hide)
	for child in control.get_children():
		if child is TextureRect: child.texture = null
