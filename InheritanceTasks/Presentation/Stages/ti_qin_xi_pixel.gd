extends HeritagePixelCanvas

const NPCS := "res://InheritanceTasks/Art/Pixel/v1/runtime/music-npcs.png"
const BOW_MOTION = preload("res://InheritanceTasks/Presentation/tiqin_bow_motion.gd")
const BOW_LAYERS := "res://InheritanceTasks/Art/Pixel/v1/runtime/tiqin-bow-v2/"
var _bow_anchors: Dictionary = {}

func paint() -> void:
	paint_background()
	var generated := bool(artwork.properties.get("generated_music", false))
	var picture := asset("res://InheritanceTasks/Art/Pixel/v3/runtime/ti_qin_xi/npcs.png" if generated else NPCS)
	var singer_pose := int(visual_state.get("partner_pose", 0))
	if picture != null:
		if generated:
			var frame_size := Vector2(picture.get_width() / 4.0, picture.get_height())
			var actors: Dictionary = visual_state.get("actors", {})
			singer_pose = HeritagePerformanceTimeline.pose_frame(actors.get("lead", {}), 3)
			var display_size := frame_size * (180.0 / frame_size.y)
			draw_texture_rect_region(picture, Rect2(Vector2(225 - display_size.x * .5, 48), display_size), Rect2(Vector2(singer_pose * frame_size.x, 0), frame_size), Color(0.82, 0.84, 0.9))
		else:
			draw_texture_rect_region(picture, Rect2(130, 32, 177, 177), Rect2(singer_pose * 128, 6 * 128, 128, 128), Color(0.82, 0.84, 0.9))
	var cue := float(visual_state.get("cue", 0.0))
	var direction := int(visual_state.get("direction", -1))
	var phase := StringName(visual_state.get("motion_phase", "idle"))
	var pose: StringName = &"ready"
	if str(visual_state.get("event_kind", "")) == "rest": pose = &"rest"
	elif phase == &"prepare": pose = &"prepare_left" if direction < 0 else &"prepare_right"
	elif phase == &"action": pose = StringName(visual_state.get("player_action", "ready"))
	if phase == &"miss": pose = &"miss"
	elif phase == &"recover": pose = &"recover"
	# Large half-body view retains the cylinder-at-waist and complete bow extent.
	var avatar_rect := Rect2(335, 105, 365, 487) if generated else Rect2(313, 108, 486, 486)
	var active_hold := bool(visual_state.get("active_hold", false))
	var closing := str(visual_state.get("player_action", "")).begins_with("bow_close_") and float(visual_state.get("feedback_age", 0.0)) > 0.0
	if generated and active_hold:
		var appearance := artwork.get_appearance(avatar_id)
		var frame_size := Vector2(appearance.frame_size)
		draw_texture_rect_region(appearance.atlas, avatar_rect, Rect2(Vector2(get_generated_bow_frame() * frame_size.x, 0), frame_size))
	elif generated:
		if closing: pose = StringName(visual_state.get("player_action", "ready"))
		paint_avatar(avatar_rect, pose)
	elif not (active_hold or closing) or not _paint_continuous_bow(avatar_rect, closing):
		paint_avatar(avatar_rect, pose)
	HeritageRhythmCues.paint(self, visual_state, {-1: Vector2(340, 525), 1: Vector2(700, 525), 0: Vector2(525, 525)} if generated else {-1: Vector2(421, 507), 1: Vector2(681, 507), 0: Vector2(542, 500)})
	paint_foreground()

func get_generated_bow_frame() -> int:
	# Five source poses advance with the judged hold, without replacing the body
	# with the old low-resolution limb rig or flipping its identity and instrument.
	var progress := clampf(float(visual_state.get("hold_progress", 0.0)), 0.0, 1.0)
	var frame := mini(4, int(progress * 5.0))
	var direction := int(visual_state.get("hold_direction", visual_state.get("player_direction", -1)))
	return frame if direction < 0 else 4 - frame

func get_bow_visual_geometry() -> Dictionary:
	if _bow_anchors.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(BOW_LAYERS + "anchors.json"))
		if data is Dictionary: _bow_anchors = data
	var anchors: Dictionary = _bow_anchors.get(str(avatar_id), {})
	var shoulder_data: Array = anchors.get("shoulder", [38, 92])
	var string_data: Array = anchors.get("string_contact", [81, 105])
	var shoulder := Vector2(shoulder_data[0], shoulder_data[1])
	var contact := Vector2(string_data[0], string_data[1])
	var closing := str(visual_state.get("player_action", "")).begins_with("bow_close_") and not bool(visual_state.get("active_hold", false))
	var settle := clampf(1.0 - float(visual_state.get("feedback_age", 0.45)) / 0.45, 0.0, 1.0) if closing else 0.0
	var direction := int(visual_state.get("hold_direction", visual_state.get("player_direction", -1)))
	return BOW_MOTION.sample(1.0 if closing else float(visual_state.get("hold_progress", 0.0)), direction, shoulder, contact, settle)

func _paint_continuous_bow(rect: Rect2, _closing: bool) -> bool:
	var folder := BOW_LAYERS + str(avatar_id).trim_suffix("_blogger") + "/"
	var body := asset(folder + "body.png")
	var upper := asset(folder + "upper_arm.png")
	var forearm := asset(folder + "forearm_hand.png")
	var bow := asset(folder + "bow.png")
	if body == null or upper == null or forearm == null or bow == null: return false
	var geometry := get_bow_visual_geometry()
	var scale := rect.size.x / 128.0
	draw_texture_rect(body, rect, false)
	var bow_rect: Rect2 = geometry.bow_rect
	draw_texture_rect(bow, Rect2(rect.position + bow_rect.position * scale, bow_rect.size * scale), false)
	_paint_arm_segment(upper, rect, geometry.shoulder, geometry.elbow, Vector2(10, 27), Vector2(68, 30))
	_paint_arm_segment(forearm, rect, geometry.elbow, geometry.wrist, Vector2(8, 25), Vector2(105, 39))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true

func _paint_arm_segment(picture: Texture2D, rect: Rect2, start: Vector2, end: Vector2, source_start: Vector2, source_end: Vector2) -> void:
	var frame_scale := rect.size.x / 128.0
	var source_vector := source_end - source_start
	var bone_vector := end - start
	var angle := bone_vector.angle() - source_vector.angle()
	var bone_scale := bone_vector.length() / source_vector.length()
	var origin := start - (source_start * bone_scale).rotated(angle)
	draw_set_transform(rect.position + origin * frame_scale, angle, Vector2.ONE * bone_scale * frame_scale)
	draw_texture(picture, Vector2.ZERO)
