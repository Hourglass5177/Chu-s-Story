class_name HeritageRhythmCues
extends RefCounted

static var _cue_font: Font
static var _panels: Dictionary = {}

## Local, audio-timed marks. This class only draws; it never awards points.
static func paint(canvas: CanvasItem, state: Dictionary, anchors: Dictionary) -> void:
	paint_judgments(canvas,state,anchors)
	if not bool(state.get("visual_assistance", true)): return
	for cue: Dictionary in state.get("cues", []):
		var direction: int = int(cue.direction)
		var origin: Vector2 = anchors.get(direction, anchors.get(0, Vector2(500, 420)))
		var index: int = int(cue.get("cue_slot", 0))
		origin += Vector2(index * 62, 0)
		var ink := Color("263e43")
		var gold := Color("f4d27e")
		var mint := Color("9dd8c6")
		if cue.kind == "rest":
			canvas.draw_style_box(_panel(Color("eee1bd")), Rect2(origin - Vector2(27, 22), Vector2(54, 44)))
			canvas.draw_rect(Rect2(origin - Vector2(11, 12), Vector2(7, 24)), ink)
			canvas.draw_rect(Rect2(origin + Vector2(4, -12), Vector2(7, 24)), ink)
			_word(canvas, origin + Vector2(0, -32), "停手", gold)
			continue
		if bool(cue.after_contact) and cue.kind != "hold": continue
		canvas.draw_circle(origin, 22, ink)
		canvas.draw_arc(origin, 22, 0, TAU, 24, gold, 3)
		if bool(cue.holding) or bool(cue.releasing):
			var bar := Rect2(origin + Vector2(34, -9), Vector2(100, 18))
			canvas.draw_style_box(_panel(ink), bar.grow(3))
			canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x * (1.0 - float(cue.hold_progress)), bar.size.y)), mint)
			if bool(cue.releasing):
				_word(canvas, origin + Vector2(0, -52), "松开", mint)
				var radius := lerpf(44.0, 22.0, float(cue.release_progress))
				canvas.draw_arc(origin, radius, 0, TAU, 32, mint, 4)
				canvas.draw_arc(origin, 13, 0.2, TAU - 0.2, 20, mint, 3)
			else:
				_word(canvas, origin + Vector2(0, -32), "按住", gold)
				canvas.draw_rect(Rect2(origin - Vector2(7, 7), Vector2(14, 14)), mint)
		else:
			var radius := lerpf(47.0, 22.0, float(cue.approach))
			canvas.draw_arc(origin, radius, 0, TAU, 32, gold, 4)
			if direction == 0:
				canvas.draw_circle(origin, 6, gold)
			else:
				canvas.draw_line(origin + Vector2(-direction * 9, 0), origin + Vector2(direction * 10, 0), gold, 4)
				canvas.draw_polyline(PackedVector2Array([origin + Vector2(direction * 3, -7), origin + Vector2(direction * 10, 0), origin + Vector2(direction * 3, 7)]), gold, 4)

static func _word(canvas: CanvasItem, center: Vector2, value: String, color: Color) -> void:
	# draw_string queues glyph atlas RIDs for rendering after this call. Retain
	# the FontFile instead of freeing a freshly duplicated font on every draw.
	if _cue_font == null: _cue_font = HeritageTelevisionStyle.pixel_font()
	var font := _cue_font
	var extent := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 30)
	canvas.draw_style_box(_panel(Color("263e43")), Rect2(center - Vector2(extent.x * .5 + 8, 30), Vector2(extent.x + 16, 40)))
	canvas.draw_string(font, center - Vector2(extent.x * .5, 0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, color)

static func _panel(color: Color) -> StyleBoxFlat:
	if _panels.has(color): return _panels[color]
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(4)
	_panels[color] = style
	return style

static func paint_judgments(canvas: CanvasItem, state: Dictionary, anchors: Dictionary) -> void:
	var slots: Dictionary = {}
	for mark: Dictionary in state.get("judgment_marks",[]):
		var direction := int(mark.direction)
		var slot := int(slots.get(direction,0))
		slots[direction] = slot+1
		var origin: Vector2 = anchors.get(direction,anchors.get(0,Vector2(500,420)))
		origin += Vector2(slot*72,-74)
		var age := float(mark.age)
		var reduced := bool(state.get("reduced_motion",false))
		var travel := 0.0 if reduced else age*20.0
		origin.y -= travel
		var grade := String(mark.grade)
		var color := Color("f4d27e") if grade=="优" else Color("9dd8c6") if grade=="良" else Color("dc8a87")
		# Keep the burst outside the text plate; at small sizes the old 22px
		# radius was mostly covered by the grade itself.
		var radius := 34.0 if reduced else 34.0+age*48.0
		if grade=="优":
			for i: int in 8:
				var axis := Vector2.RIGHT.rotated(i*PI*.25)
				var length := 15.0 if i%2==0 else 8.0
				canvas.draw_line(origin+axis*radius,origin+axis*(radius+length),color,4)
				if not reduced and i%2==0:
					var point := origin+axis*(radius+length+5)
					canvas.draw_colored_polygon(PackedVector2Array([point+Vector2(0,-4),point+Vector2(4,0),point+Vector2(0,4),point+Vector2(-4,0)]),color)
		elif grade=="良": canvas.draw_arc(origin,radius,0,TAU,32,color,3)
		else:
			canvas.draw_arc(origin,radius,0.3,PI-.3,16,color,3)
			canvas.draw_arc(origin,radius,PI+.3,TAU-.3,16,color,3)
		_word(canvas,origin+Vector2(0,8),grade,color)
		if not String(mark.reason).is_empty(): _word(canvas,origin+Vector2(0,44),String(mark.reason),color)
