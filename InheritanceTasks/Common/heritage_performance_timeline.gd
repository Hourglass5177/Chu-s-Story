class_name HeritagePerformanceTimeline
extends RefCounted

## Pure audio-time sampling. No scoring, input, frame-delta accumulation or audio
## playback here. Later clips on one actor override its longer background pose.
static func actors_at(clips: Array[Dictionary], time_ms: int) -> Dictionary:
	var actors: Dictionary = {}
	for clip: Dictionary in clips:
		var begin := int(clip.start_ms)
		var end := int(clip.end_ms)
		if time_ms < begin or time_ms >= end: continue
		var actor := str(clip.actor)
		if actors.has(actor) and int(actors[actor].start_ms) > begin: continue
		var state := clip.duplicate(true)
		state.progress = clampf(float(time_ms - begin) / float(end - begin), 0.0, 1.0)
		state.elapsed = (time_ms - begin) / 1000.0
		actors[actor] = state
	return actors

static func pose_frame(actor: Dictionary, fallback: int = 0) -> int:
	if actor.is_empty(): return fallback
	var frames: Array = actor.get("frames", [fallback])
	if frames.is_empty(): return fallback
	var phase := float(actor.get("progress", 0.0))
	var cycle_ms := int(actor.get("cycle_ms", 0))
	if cycle_ms > 0: phase = fmod(float(actor.elapsed) * 1000.0, cycle_ms) / cycle_ms
	return int(frames[mini(frames.size() - 1, int(phase * frames.size()))])
