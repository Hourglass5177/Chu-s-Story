extends HeritagePixelCanvas

const NPCS := "res://InheritanceTasks/Art/Pixel/v1/runtime/music-npcs.png"

func paint() -> void:
	paint_background()
	var cue := float(visual_state.get("cue", 0.0))
	var partner_turn := StringName(visual_state.get("ensemble_turn", "partners")) == &"partners"
	var partner_pose := int(visual_state.get("partner_pose", 0))
	var generated := bool(artwork.properties.get("generated_music", false))
	if generated:
		var actors: Dictionary = visual_state.get("actors", {})
		_generated_npc(0, HeritagePerformanceTimeline.pose_frame(actors.get("partner_left", {}), 3), Vector2(45, 139))
		_generated_npc(1, HeritagePerformanceTimeline.pose_frame(actors.get("partner_right", {}), 3), Vector2(329, 139))
	else:
		_npc(0, partner_pose if partner_turn else (3 if cue > 0.3 else 4), Rect2(93, 210, 250, 250))
		_npc(1, partner_pose if partner_turn else (3 if cue > 0.3 else 4), Rect2(657, 224, 233, 232))
	var phase := StringName(visual_state.get("motion_phase", "idle"))
	var pose: StringName = &"ready"
	if phase == &"prepare" and not partner_turn: pose = &"prepare"
	elif phase == &"action": pose = &"pluck"
	elif phase == &"miss": pose = &"miss"
	elif phase == &"recover": pose = &"recover"
	var player_rect := Rect2(384, 188, 232, 360) if generated else Rect2(348, 232, 310, 310)
	paint_avatar(player_rect, pose)
	HeritageRhythmCues.paint(self, visual_state, {0: Vector2(453, 452)})
	paint_foreground()

func _generated_npc(row: int, frame: int, at: Vector2) -> void:
	var texture := asset("res://InheritanceTasks/Art/Pixel/v3/runtime/laohekou_si_xian/npcs.png")
	if texture == null: return
	var cell := Vector2(texture.get_width() / 8.0, texture.get_height())
	draw_texture_rect_region(texture, Rect2(at * 2.0, Vector2(260, 202)), Rect2(Vector2((row * 4 + frame) * cell.x, 0), cell))

func _npc(row: int, column: int, rect: Rect2) -> void:
	var picture := asset(NPCS)
	if picture != null: draw_texture_rect_region(picture, rect, Rect2(column * 128, row * 128, 128, 128))
