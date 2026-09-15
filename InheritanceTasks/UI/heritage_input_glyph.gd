extends Control

## A readable device silhouette with a tiny physical press. These controls use
## the same binding token as input; no instruction is baked into a bitmap.
var glyph: String = "key_space"
var caption: String = "空格"
var font: Font
var font_size: int = 20
var down: bool = false
var _press: float = 0.0
var _boxes: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(false)

func set_pressed(value: bool) -> void:
	if down == value: return
	down = value
	if not is_visible_in_tree():
		_press = 1.0 if down else 0.0
		set_process(false)
		return
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		_press = 1.0 if down else 0.0
		set_process(false)
		return
	_press = move_toward(_press,1.0 if down else 0.0,delta * 12.0)
	queue_redraw()
	if is_equal_approx(_press,1.0 if down else 0.0): set_process(false)

func _draw() -> void:
	var ink := Color("47363c")
	var paper := Color("f7e7bd")
	var accent := Color("cb9063") if down else Color("648b79")
	var unit := minf(size.x,size.y) / 32.0
	var offset := Vector2(0,roundf(_press * unit * 2.0))
	if glyph.begins_with("mouse_"):
		var box := Rect2(Vector2(size.x*.5-9*unit,2*unit)+offset,Vector2(18,27)*unit)
		draw_style_box(_box(paper,ink,unit*2),box)
		var button := Rect2(box.position+Vector2(unit*2,unit*2),Vector2(6,10)*unit)
		if glyph == "mouse_right": button.position.x += unit*8
		if glyph in ["mouse_left","mouse_right"]: draw_rect(button,accent)
		draw_line(box.position+Vector2(9,2)*unit,box.position+Vector2(9,12)*unit,ink,unit)
		var wheel := Rect2(box.position+Vector2(7,5)*unit,Vector2(4,5)*unit)
		draw_rect(wheel,accent if "wheel" in glyph or glyph == "mouse_middle" else ink)
		if "wheel" in glyph:
			_text("↑" if glyph.ends_with("up") else "↓",Rect2(Vector2(size.x*.5+11*unit,unit),Vector2(12,27)*unit),ink)
	elif glyph in ["pad_south","pad_north","pad_east","pad_west"]:
		var center := size*.5+offset
		var positions := {"pad_north":Vector2(0,-9),"pad_south":Vector2(0,9),"pad_west":Vector2(-9,0),"pad_east":Vector2(9,0)}
		for key: String in positions:
			var point: Vector2 = center + positions[key]*unit
			draw_circle(point,6*unit,ink)
			draw_circle(point,4.5*unit,accent if key == glyph else paper)
		if HeritageMinigamePreferences.gamepad_glyph_style() != "position":
			_text(caption,Rect2(center+positions[glyph]*unit-Vector2(6,8)*unit,Vector2(12,16)*unit),paper)
	else:
		var bounds := Rect2(Vector2(unit,unit)+offset,size-Vector2(2*unit,4*unit))
		draw_style_box(_box(Color("735445"),ink,unit),Rect2(bounds.position+Vector2(0,unit*2),bounds.size))
		draw_style_box(_box(accent if down else paper,ink,unit),bounds)
		_text(caption,bounds,ink)

func _box(fill: Color, outline: Color, width: float) -> StyleBoxFlat:
	var key := "%s:%s:%d" % [fill.to_html(),outline.to_html(),maxi(1,roundi(width))]
	if _boxes.has(key): return _boxes[key]
	var box := StyleBoxFlat.new()
	box.bg_color = fill; box.border_color = outline
	box.anti_aliasing = false
	box.set_border_width_all(maxi(1,roundi(width)))
	_boxes[key] = box
	return box

func _text(value: String, bounds: Rect2, color: Color) -> void:
	if font == null: return
	var text_size := font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
	draw_string(font,bounds.position+Vector2((bounds.size.x-text_size.x)*.5,(bounds.size.y-font.get_height(font_size))*.5+font.get_ascent(font_size)),value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)
