extends HeritagePixelCanvas

const NPCS := "res://InheritanceTasks/Art/Pixel/v1/runtime/music-npcs.png"

func paint() -> void:
	paint_background()
	var cue := float(visual_state.get("cue", 0.0))
	var lead_turn := bool(visual_state.get("lead_singer_turn", true))
	var lead_pose := int(visual_state.get("partner_pose", 0)) if lead_turn else 0
	if not lead_turn: lead_pose = 3 if cue > 0.45 else 1
	var generated := bool(artwork.properties.get("generated_music", false))
	var picture := asset("res://InheritanceTasks/Art/Pixel/v3/runtime/jingzhou_hua_gu_xi/npcs.png" if generated else NPCS)
	if picture != null:
		if generated:
			var cell := Vector2(picture.get_width() / 4.0, picture.get_height())
			var actors: Dictionary = visual_state.get("actors", {})
			var step := HeritagePerformanceTimeline.pose_frame(actors.get("lead", {}), 3 if cue > 0.3 else 2)
			draw_texture_rect_region(picture, Rect2(120, 10, 270, 270), Rect2(Vector2(step * cell.x, 0), cell))
		else:
			draw_texture_rect_region(picture, Rect2(207, 76, 237, 237), Rect2(lead_pose * 128, 4 * 128, 128, 128))
	var phase := StringName(visual_state.get("motion_phase", "idle"))
	var pose: StringName = &"ready"
	if phase == &"prepare": pose = &"prepare"
	elif phase == &"action": pose = StringName(visual_state.get("player_action", "voice_short"))
	elif phase == &"miss": pose = &"miss"
	elif phase == &"recover": pose = &"recover"
	if bool(visual_state.get("active_hold", false)): pose = &"voice_sustain"
	if bool(visual_state.get("release_cue", false)): pose = &"voice_close" if not bool(visual_state.get("active_hold", false)) else &"voice_sustain"
	paint_avatar(Rect2(582, 190, 245, 380) if generated else Rect2(565, 216, 330, 330), pose)
	HeritageRhythmCues.paint(self, visual_state, {0: Vector2(714, 466)})
	paint_foreground()
