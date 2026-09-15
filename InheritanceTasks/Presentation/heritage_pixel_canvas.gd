class_name HeritagePixelCanvas
extends Control

## Small art-only interface shared by independent stage scenes.
var artwork: HeritageTaskPresentation
var avatar_id: StringName
var visual_state: Dictionary = {}
var _textures: Dictionary = {}
var _local_action: StringName = &""
var _local_action_time: float = 0.0
var _last_visual_time: float = -1.0
var _last_action_serial: int = -1
var _drawn_animation: StringName = &""
var _drawn_serial: int = -1
var _animation_began: float = 0.0
var _animation_last_clock: float = -1.0

func receive_visual_state(state: Dictionary) -> void:
	# The task clock freezes during pause. A state transition starts its own
	# animation; a later action never begins at a random global-time frame.
	var now := float(state.get("animation_time", 0.0))
	var next_action := StringName(state.get("pose", state.get("action", "ready")))
	var serial := int(state.get("action_serial", -1))
	if state.has("action_time"):
		_local_action = next_action
		_local_action_time = maxf(0.0, float(state.action_time))
	elif next_action != _local_action or serial != _last_action_serial or now < _last_visual_time:
		_local_action = next_action
		_local_action_time = 0.0
	elif _last_visual_time >= 0.0:
		_local_action_time += clampf(now - _last_visual_time, 0.0, 0.25)
	_last_visual_time = now
	_last_action_serial = serial
	visual_state = state
	queue_redraw()

func local_action_time() -> float:
	return _local_action_time

func avatar_texture(animation: StringName) -> Texture2D:
	var appearance := artwork.get_appearance(avatar_id)
	if appearance == null: return null
	var frames := appearance.sprite_frames
	if frames == null: return appearance.portrait
	var selected := animation if frames.has_animation(animation) else &"ready"
	if not frames.has_animation(selected): return appearance.portrait
	var count := frames.get_frame_count(selected)
	if count == 0: return appearance.portrait
	# A preparation/closing transition must start at its first frame even when
	# no new input serial was emitted. Use the paused task clock, never wall time.
	var clock_time := float(visual_state.get("song_time_ms", animation_time() * 1000.0)) / 1000.0
	var serial := int(visual_state.get("action_serial", -1))
	if selected != _drawn_animation or serial != _drawn_serial or clock_time < _animation_last_clock:
		_animation_began = clock_time
		_drawn_animation = selected
		_drawn_serial = serial
	_animation_last_clock = clock_time
	var weighted_time := maxf(0.0, clock_time - _animation_began) * frames.get_animation_speed(selected)
	var total := 0.0
	for i in count: total += frames.get_frame_duration(selected, i)
	weighted_time = fmod(weighted_time, total) if frames.get_animation_loop(selected) else minf(weighted_time, total - 0.00001)
	for i in count:
		weighted_time -= frames.get_frame_duration(selected, i)
		if weighted_time < 0.0: return frames.get_frame_texture(selected, i)
	return frames.get_frame_texture(selected, count - 1)

func paint_native(path: String, at: Vector2, source: Rect2 = Rect2()) -> void:
	var picture := asset(path)
	if picture == null: return
	var region := source if source.has_area() else Rect2(Vector2.ZERO, picture.get_size())
	draw_texture_rect_region(picture, Rect2(at.round() * 2.0, region.size * 2.0), region)

func _draw() -> void:
	paint()

func paint() -> void:
	paint_background()
	paint_avatar(Rect2(160, 145, 320, 380), action())
	paint_foreground()

func paint_background() -> void:
	if artwork.background != null:
		draw_texture_rect(artwork.background, Rect2(Vector2.ZERO, Vector2(artwork.logical_stage_size)), false)

func paint_foreground() -> void:
	if artwork.foreground != null:
		draw_texture_rect(artwork.foreground, Rect2(Vector2.ZERO, Vector2(artwork.logical_stage_size)), false)

func action() -> StringName:
	return StringName(visual_state.get("action", "ready"))

func animation_time() -> float:
	return float(visual_state.get("animation_time", 0.0))

func decoration_time() -> float:
	# Freeze ambient loops only; input, anticipation and recovery poses retain time.
	return 0.0 if bool(visual_state.get("reduced_motion", false)) else animation_time()

func paint_avatar(rect: Rect2, animation: StringName = &"ready", who: StringName = &"") -> void:
	if artwork.version >= 2 and who.is_empty():
		var native := avatar_texture(animation)
		if native != null: draw_texture_rect(native, rect, false)
		return
	var appearance := artwork.get_appearance(avatar_id if who.is_empty() else who)
	if appearance == null: return
	var picture: Texture2D = appearance.portrait
	if appearance.sprite_frames != null:
		var name_to_play: StringName = animation if appearance.sprite_frames.has_animation(animation) else &"ready"
		if appearance.sprite_frames.has_animation(name_to_play):
			var count := appearance.sprite_frames.get_frame_count(name_to_play)
			var speed := appearance.sprite_frames.get_animation_speed(name_to_play)
			var frame := int(animation_time() * speed) % maxi(1, count)
			picture = appearance.sprite_frames.get_frame_texture(name_to_play, frame)
	if picture != null: draw_texture_rect(picture, rect, false)

func asset(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _textures[path] as Texture2D

func paint_asset(path: String, rect: Rect2) -> void:
	var picture := asset(path)
	if picture != null: draw_texture_rect(picture, rect, false)
