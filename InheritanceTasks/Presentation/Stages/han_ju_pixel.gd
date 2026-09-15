extends HeritagePixelCanvas

const NPCS := "res://InheritanceTasks/Art/Pixel/v1/runtime/music-npcs.png"

func paint() -> void:
	paint_background()
	var actor_x := float(visual_state.get("actor_x", 0.3)) * 1000.0
	var lane := int(visual_state.get("light_lane", -1))
	var target_x := 300.0 if lane < 0 else 700.0
	var crossing := bool(visual_state.get("actor_crossing", false))
	var lit := bool(visual_state.get("light_on_actor", true))
	var generated := bool(artwork.properties.get("generated_music", false))
	# Ambient stage light always keeps the actor legible; this cone is only emphasis.
	var lamp_origin := Vector2(155 + 15 * lane, 337) if generated else (Vector2(98, 400) if lane < 0 else Vector2(263, 404))
	var floor_y := 342.0 if generated else 412.0
	draw_colored_polygon(PackedVector2Array([lamp_origin, Vector2(target_x - 72, 115), Vector2(target_x + 72, 115), Vector2(target_x + 86, floor_y), Vector2(target_x - 86, floor_y)]), Color(1.0, 0.88, 0.62, 0.12))
	draw_ellipse_marker(Vector2(target_x, floor_y), Color(1.0, 0.86, 0.55, 0.28))
	var pose := 1 + int(animation_time() * 4.0) % 3 if crossing else (4 if int(animation_time() * 1.3) % 3 == 1 else 0)
	var picture := asset("res://InheritanceTasks/Art/Pixel/v3/runtime/han_ju/npcs.png" if generated else NPCS)
	if picture != null:
		if generated:
			var frame_size := Vector2(picture.get_width() / 8.0, picture.get_height())
			# Walking alone cycles. A settled actor holds the corresponding arrival pose.
			var actors: Dictionary = visual_state.get("actors", {})
			var actor: Dictionary = actors.get("actor", {})
			pose = HeritagePerformanceTimeline.pose_frame(actor) if crossing else (6 if actor_x < 500 else 5)
			draw_texture_rect_region(picture, Rect2(actor_x - 90, 60, 180, 270), Rect2(Vector2(pose * frame_size.x, 0), frame_size), Color.WHITE if lit else Color(0.80, 0.80, 0.84))
		else:
			draw_texture_rect_region(picture, Rect2(actor_x - 116, 185, 232, 232), Rect2(pose * 128, 5 * 128, 128, 128), Color.WHITE if lit else Color(0.80, 0.80, 0.84))
	var player_pose: StringName = &"spotlight_left" if lane < 0 else &"spotlight_right"
	var phase := StringName(visual_state.get("motion_phase", "idle"))
	if not generated:
		if phase == &"prepare" and lane < 0: player_pose = &"prepare"
		elif phase == &"miss" and lane > 0: player_pose = &"miss"
		elif phase == &"recover" and lane < 0: player_pose = &"recover"
	paint_avatar(Rect2(47, 307, 216, 288) if generated else Rect2(40, 342, 250, 250), player_pose)
	var cue_y := 382.0 if generated else 465.0
	HeritageRhythmCues.paint(self, visual_state, {-1: Vector2(300, cue_y), 1: Vector2(700, cue_y), 0: Vector2(500, cue_y)})
	paint_foreground()

func draw_ellipse_marker(center: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i: int in 32:
		var angle := float(i) * TAU / 32.0
		points.append(center + Vector2(cos(angle) * 82, sin(angle) * 16))
	draw_colored_polygon(points, color)
