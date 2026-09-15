extends HeritagePixelCanvas

const TEACHER := "res://InheritanceTasks/Art/Pixel/v1/runtime/craft/gu_pen_ge-teacher.png"
var _hint_font: Font

func paint() -> void:
	paint_background()
	var showing := bool(visual_state.get("showing", true))
	var teacher_frame := int(visual_state.get("teacher_frame", 0))
	var generated := bool(artwork.properties.get("generated_music", false))
	var teacher := asset("res://InheritanceTasks/Art/Pixel/v3/runtime/gu_pen_ge/npcs.png" if generated else TEACHER)
	if teacher != null:
		var cell := Vector2(teacher.get_width() / 4.0, teacher.get_height()) if generated else Vector2(160, 160)
		draw_texture_rect_region(teacher, Rect2(162, 170, 245, 380) if generated else Rect2(90, 180, 340, 340), Rect2(Vector2(clampi(teacher_frame, 0, 3) * cell.x, 0), cell))
	var pose: StringName = &"prepare" if not showing else &"ready"
	if float(visual_state.get("feedback_age", 0.0)) > .2: pose = &"hold"
	elif float(visual_state.get("feedback_age", 0.0)) > 0.0: pose = &"recover"
	paint_avatar(Rect2(597, 170, 245, 380) if generated else Rect2(558, 180, 340, 340), pose)
	var highlight := Rect2(162, 548, 245, 5) if showing else Rect2(597, 548, 245, 5)
	draw_rect(highlight, Color("f5d990"))
	for i: int in 3:
		draw_rect(Rect2(777 + i * 51, 40, 35, 23), Color("ead8b3") if i < int(visual_state.get("rounds_passed", 0)) else Color("6b5c49"))
	HeritageRhythmCues.paint(self, visual_state, {0: Vector2(720, 407)})
	if _hint_font == null: _hint_font = HeritageTelevisionStyle.pixel_font()
	var font := _hint_font
	var label := str(visual_state.get("local_hint", "听"))
	var text_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	var panel_width := maxf(80, text_width + 32)
	var panel_x := (284.0 if showing else 720.0) - panel_width * 0.5
	draw_style_box(HeritageRhythmCues._panel(Color("263e43")), Rect2(panel_x, 100, panel_width, 48))
	draw_string(font, Vector2(panel_x + 16, 133), label, HORIZONTAL_ALIGNMENT_LEFT, text_width, 24, Color("fff1cc"))
