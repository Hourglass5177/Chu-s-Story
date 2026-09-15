extends Control

## Clear broadcast state over the real game canvas; never consumes input.
var state: Dictionary = {}
var logo: Texture2D
var font: Font
var _started_at: int = -1
var _last_phase := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	font = HeritageTelevisionStyle.pixel_font()
	logo = load("res://InheritanceTasks/Art/Pixel/v3/runtime/ui/chuwu-tv-v1.png")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(false)

func update_instruction(value: Dictionary) -> void:
	var phase := String(value.get("phase","live"))
	if phase=="live" and _last_phase=="countdown":
		_started_at = Time.get_ticks_msec()
		set_process(true)
	_last_phase = phase
	state = value
	queue_redraw()

func _process(_delta: float) -> void:
	queue_redraw()
	if Time.get_ticks_msec()-_started_at>450: set_process(false)

func _draw() -> void:
	if state.is_empty(): return
	var scale_factor := size.x/1000.0
	draw_set_transform(Vector2.ZERO,0,Vector2.ONE*scale_factor)
	var height := size.y/scale_factor
	var teaching := bool(state.get("teaching",false))
	var phase := String(state.get("phase","live"))
	var cream := Color("fff0cc")
	if teaching:
		draw_rect(Rect2(0,0,1000,60),Color("235b57"))
		draw_rect(Rect2(3,3,994,height-6),Color("69b8aa"),false,5)
		_text("玩法教学 · "+("看示范" if phase=="demo" else "跟着练"),Vector2(610,41),32,cream)
		var hint := String(state.get("text",""))
		if not hint.is_empty():
			draw_rect(Rect2(160,height-58,680,52),Color("235b57"))
			_text(hint,Vector2(500,height-22),30,cream)
	else:
		draw_rect(Rect2(2,2,996,height-4),Color("d2af69"),false,2)
	if logo != null: draw_texture_rect(logo,Rect2(14,13,118,35),false)
	if phase in ["countdown","resume"]:
		draw_rect(Rect2(0,0,1000,height),Color(0.06,0.08,0.09,.5))
		var title := "继续" if phase=="resume" else "准备"
		_text(title,Vector2(500,height*.5-90),42,cream)
		var number := str(maxi(1,int(state.get("countdown",3))))
		if "松开" in String(state.get("text","")): number = "松开按键"
		_text(number,Vector2(500,height*.5+55),112 if number.length()==1 else 48,cream)
	elif _started_at>=0 and Time.get_ticks_msec()-_started_at<=450:
		_text("开始",Vector2(500,height*.5+36),84,cream)
	draw_set_transform(Vector2.ZERO)

func _text(value: String, center: Vector2, point_size: int, color: Color) -> void:
	var extent := font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,point_size)
	var position := center-Vector2(extent.x*.5,0)
	draw_string_outline(font,position,value,HORIZONTAL_ALIGNMENT_LEFT,-1,point_size,4,Color("302c32"))
	draw_string(font,position,value,HORIZONTAL_ALIGNMENT_LEFT,-1,point_size,color)
