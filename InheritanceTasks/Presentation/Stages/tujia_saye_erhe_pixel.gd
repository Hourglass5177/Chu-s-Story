extends HeritagePixelCanvas

const NPCS := "res://InheritanceTasks/Art/Pixel/v1/runtime/music-npcs.png"

func paint() -> void:
	paint_background()
	var cue := float(visual_state.get("cue", 0.0))
	var direction := int(visual_state.get("direction", -1))
	var rest := str(visual_state.get("event_kind", "")) == "rest"
	var lead_pose := 0
	if cue > 0.7 and not rest: lead_pose = 4 if direction < 0 else 2
	elif cue > 0.0 and not rest: lead_pose = 4 if direction < 0 else 1
	if bool(artwork.properties.get("generated_music", false)):
		var actors: Dictionary = visual_state.get("actors", {})
		var leader: Dictionary = actors.get("leader", {})
		var phase_index := HeritagePerformanceTimeline.pose_frame(leader)
		direction = int(leader.get("direction", direction))
		_generated_npc(0, phase_index, Vector2(202, 55), direction > 0)
		_generated_npc(0, phase_index, Vector2(112, 96), direction > 0)
		_generated_npc(0, phase_index, Vector2(306, 96), direction > 0)
		_generated_npc(1, HeritagePerformanceTimeline.pose_frame(actors.get("drummer", {})), Vector2(397, 73))
	else:
		_npc(3, 2 if cue > 0.8 else (1 if cue > 0.4 else 0), Rect2(82, 205, 210, 210))
		_npc(2, lead_pose, Rect2(415, 160, 172, 172))
		_npc(2, lead_pose, Rect2(258, 314, 174, 174))
		_npc(2, lead_pose, Rect2(654, 314, 174, 174))
	var pose: StringName = &"ready"
	var phase := StringName(visual_state.get("motion_phase", "idle"))
	if rest: pose = &"rest"
	elif phase == &"prepare": pose = &"prepare_left" if direction < 0 else &"prepare_right"
	elif phase == &"action": pose = StringName(visual_state.get("player_action", "ready"))
	if phase == &"miss": pose = &"miss"
	elif phase == &"recover": pose = &"recover"
	paint_avatar(Rect2(404, 296, 192, 256) if bool(artwork.properties.get("generated_music", false)) else Rect2(390, 325, 220, 220), pose)
	HeritageRhythmCues.paint(self, visual_state, {-1: Vector2(440, 542), 1: Vector2(560, 542), 0: Vector2(500, 500)})
	paint_foreground()

func _generated_npc(row: int, frame: int, at: Vector2, opposite: bool = false) -> void:
	# Supporting teacher's symmetric teaching step; blogger has independently
	# generated left/right poses and is never mirrored.
	var texture := asset("res://InheritanceTasks/Art/Pixel/v3/runtime/tujia_saye_erhe/npcs.png")
	if texture == null: return
	var cell := Vector2(texture.get_width() / 8.0, texture.get_height())
	if opposite:
		draw_set_transform((at + Vector2(96, 0)) * 2.0, 0.0, Vector2(-1, 1))
		draw_texture_rect_region(texture, Rect2(0, 0, 192, 256), Rect2(Vector2(frame * cell.x, 0), cell))
		draw_set_transform(Vector2.ZERO)
	else:
		draw_texture_rect_region(texture, Rect2(at * 2.0, Vector2(192, 256)), Rect2(Vector2((row * 4 + frame) * cell.x, 0), cell))

func _npc(row: int, column: int, rect: Rect2) -> void:
	var picture := asset(NPCS)
	if picture != null: draw_texture_rect_region(picture, rect, Rect2(column * 128, row * 128, 128, 128))
