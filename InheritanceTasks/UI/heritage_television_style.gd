class_name HeritageTelevisionStyle
extends RefCounted

const CREAM := Color("ead5ab")
const INK := Color("39271e")
const GOLD := Color("ffd77b")
const V2_ROOT := "res://InheritanceTasks/Art/Pixel/v2/"
const V2_INK := Color("2a2633")
const V2_CREAM := Color("f4dfad")
const V2_ACCENT := Color("e5bc7f")
const V2_GREEN := Color("354e41")
static var _pixel_texture_cache: Dictionary[String, Texture2D] = {}
static var _pixel_font_cache: Dictionary[bool, Font] = {}
static var _pixel_source_cache: Dictionary[String, Texture2D] = {}
static var _pixel_box_cache: Dictionary[String, StyleBox] = {}
static var texture_upload_count: int = 0
static var font_creation_count: int = 0


static func pixel_font(auxiliary: bool = false) -> Font:
	if _pixel_font_cache.has(auxiliary): return _pixel_font_cache[auxiliary]
	var path := V2_ROOT + "fonts/fusion-pixel-%dpx-proportional-zh_hans.ttf" % (10 if auxiliary else 12)
	var font := load(path) as FontFile
	if font == null: return null
	var instance := font.duplicate() as FontFile
	instance.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	instance.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	instance.hinting = TextServer.HINTING_NONE
	instance.generate_mipmaps = false
	# Keep the author's 10/12-pixel glyph grid before the host canvas scales it.
	instance.fixed_size = 10 if auxiliary else 12
	instance.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	_pixel_font_cache[auxiliary] = instance
	font_creation_count += 1
	return instance


static func pixel_box(asset: String, margin: float = 12.0, pixel_factor: float = 1.0) -> StyleBox:
	# Callers use these as immutable theme resources. Reuse the same StyleBox
	# instead of invalidating every button's theme with a newly allocated copy.
	var key := "%s|%.4f|%.4f" % [asset,margin,pixel_factor]
	if _pixel_box_cache.has(key): return _pixel_box_cache[key]
	var path := V2_ROOT + "runtime/ui/" + asset + ".png"
	if ResourceLoader.exists(path):
		var box := StyleBoxTexture.new()
		box.texture = _pixel_texture(path, pixel_factor)
		box.texture_margin_left = 6 * pixel_factor
		box.texture_margin_top = 6 * pixel_factor
		box.texture_margin_right = 6 * pixel_factor
		box.texture_margin_bottom = 6 * pixel_factor
		box.content_margin_left = margin
		box.content_margin_top = margin
		box.content_margin_right = margin
		box.content_margin_bottom = margin
		_pixel_box_cache[key] = box
		return box
	# A missing cosmetic component must not break a running challenge.
	var fallback := StyleBoxFlat.new()
	fallback.bg_color = V2_CREAM
	fallback.border_color = V2_ACCENT
	fallback.set_border_width_all(2)
	fallback.set_content_margin_all(margin)
	return fallback


static func pixel_button(control: Button, margin: float = 12.0, pixel_factor: float = 1.0) -> void:
	control.focus_mode = Control.FOCUS_ALL
	control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	control.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var asset := "button" if state == "normal" else "button_" + state
		control.add_theme_stylebox_override(state, pixel_box(asset, margin, pixel_factor))
		var text_color := Color("756044") if state == "disabled" else V2_INK
		control.add_theme_color_override("font_color" if state == "normal" else "font_%s_color" % state, text_color)


static func _pixel_texture(path: String, factor: float) -> Texture2D:
	if not _pixel_source_cache.has(path): _pixel_source_cache[path] = load(path) as Texture2D
	var source := _pixel_source_cache[path]
	var target_size := Vector2i((source.get_size() * factor).round())
	var key := path + str(target_size)
	if _pixel_texture_cache.has(key): return _pixel_texture_cache[key]
	var bitmap := source.get_image()
	if bitmap.is_compressed(): bitmap.decompress()
	bitmap.resize(maxi(1, target_size.x), maxi(1, target_size.y), Image.INTERPOLATE_NEAREST)
	var texture := ImageTexture.create_from_image(bitmap)
	# Never flush all live sizes: changing window/device then re-uploaded them.
	_pixel_texture_cache[key] = texture
	texture_upload_count += 1
	return texture


static func pixel_icon(asset: String, factor: float) -> Texture2D:
	var path := V2_ROOT + "runtime/ui/" + asset + ".png"
	return _pixel_texture(path, factor) if ResourceLoader.exists(path) else null


static func pixel_slider(slider: HSlider, factor: float) -> void:
	var track := pixel_icon("slider_track", factor)
	var grip := pixel_icon("slider_grip", factor)
	if track != null:
		var rail := StyleBoxTexture.new()
		rail.texture = track
		rail.texture_margin_left = 4 * factor
		rail.texture_margin_right = 4 * factor
		rail.texture_margin_top = 2 * factor
		rail.texture_margin_bottom = 2 * factor
		rail.content_margin_top = 4 * factor
		rail.content_margin_bottom = 4 * factor
		slider.add_theme_stylebox_override("slider", rail)
		var filled := StyleBoxFlat.new()
		filled.bg_color = Color("50878a")
		filled.border_color = Color("624039")
		filled.set_border_width_all(maxi(1, int(factor)))
		filled.content_margin_top = 4 * factor
		filled.content_margin_bottom = 4 * factor
		slider.add_theme_stylebox_override("grabber_area", filled)
		slider.add_theme_stylebox_override("grabber_area_highlight", filled)
	if grip != null:
		for state: String in ["grabber", "grabber_highlight", "grabber_disabled"]:
			slider.add_theme_icon_override(state, grip)
	slider.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


static func panel() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = CREAM
	box.border_color = Color("875427")
	box.set_border_width_all(4)
	box.shadow_color = Color(0.09, 0.05, 0.03, 0.7)
	box.shadow_size = 8
	box.shadow_offset = Vector2(0, 5)
	return box


static func button(button: Button, knob: bool = false) -> void:
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("e6c995")
		style.border_color = Color("76502c")
		if state == "hover": style.bg_color = Color("fff0c8")
		if state == "pressed": style.bg_color = Color("c39658")
		if state == "disabled": style.bg_color = Color("99846c")
		style.set_border_width_all(3)
		style.border_width_bottom = 6 if state != "pressed" else 2
		if knob:
			style.bg_color = Color(1, 0.87, 0.5, 0.08 if state == "hover" else 0.0)
			style.set_border_width_all(0)
		button.add_theme_stylebox_override(state, style)
		button.add_theme_color_override("font_%s_color" % state if state != "normal" else "font_color", INK)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = GOLD
	focus.set_border_width_all(4)
	focus.expand_margin_left = 3
	focus.expand_margin_top = 3
	focus.expand_margin_right = 3
	focus.expand_margin_bottom = 3
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_color_override("font_focus_color", INK)
