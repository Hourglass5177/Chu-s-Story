class_name HeritageMusicChart
extends Resource

@export var version: int = 1
@export_file("*.ogg") var audio_path: String = ""
@export var audio_sha256: String = ""
@export var end_ms: int = 40000
## id, time_ms, kind (tap/hold/switch/rest), direction, end_ms, cue_ms.
@export var events: Array[Dictionary] = []
@export var presentation: Array[Dictionary] = []
@export_multiline var annotation_note: String = ""
@export_file("*.ogg") var tutorial_audio_path: String = ""
@export var feedback_key: String = ""
@export var sections: Array[Dictionary] = []
## Independent actor clips; never fed to the judge. Times use the audio clock.
@export var choreography: Array[Dictionary] = []
## Each step plays an exported excerpt of the actual game mix, with local times.
@export var tutorial_steps: Array[Dictionary] = []
@export var production_status: String = "legacy_candidate"

func validate() -> String:
	if version < 1 or audio_path.is_empty() or audio_sha256.length() != 64 or end_ms <= 0:
		return "谱面元数据不完整"
	var ids: Dictionary = {}
	var previous: int = -1
	var rest_count: int = 0
	for e: Dictionary in events:
		var t: int = int(e.get("time_ms", -1))
		var ending: int = int(e.get("end_ms", t))
		var kind: String = str(e.get("kind", ""))
		var id: String = str(e.get("id", ""))
		if id.is_empty() or ids.has(id) or t < previous or t < 0 or ending >= end_ms or ending < t:
			return "谱面事件次序或编号无效"
		if kind not in ["tap", "hold", "switch", "rest"] or int(e.get("direction", 0)) not in [-1, 0, 1]:
			return "谱面动作无效"
		if int(e.get("cue_ms", -1)) < 0 or (kind in ["hold", "rest"] and ending <= t):
			return "谱面提示或时值无效"
		if str(e.get("rest_policy", "no_press")) not in ["no_press", "release_required", "keep_position"]:
			return "休止规则无效：" + id
		ids[id] = true
		previous = t
		if kind == "rest": rest_count += 1
	if events.is_empty() or rest_count * 5 > events.size(): return "休止比例无效"
	if version >= 2:
		for i: int in events.size():
			var a: Dictionary = events[i]
			for j: int in range(i + 1, events.size()):
				var b: Dictionary = events[j]
				if a.kind == "hold" and b.kind != "rest" and int(a.direction) == int(b.direction) and int(b.time_ms) <= int(a.end_ms) + 220:
					return "同侧长按与下一动作重叠：%s / %s" % [a.id, b.id]
				if a.kind != "rest" and b.kind != "rest" and int(a.direction) == int(b.direction) and int(b.time_ms) - int(a.time_ms) < 360:
					return "同侧两次操作窗口重叠：%s / %s" % [a.id, b.id]
				if a.kind == "rest" and b.kind != "rest" and int(b.time_ms) - 180 <= int(a.end_ms):
					return "休止与操作窗口冲突：%s / %s" % [a.id, b.id]
				if a.kind == "hold" and b.kind == "rest" and int(b.time_ms) <= int(a.end_ms) + 220:
					return "长按收尾与休止窗口冲突：%s / %s" % [a.id, b.id]
		for cue: Dictionary in presentation:
			if not ids.has(str(cue.get("id", ""))): return "提示引用不存在的判定事件"
	if version >= 3:
		var motion_error := validate_choreography(choreography, end_ms, ids)
		if not motion_error.is_empty(): return motion_error
		for step: Dictionary in tutorial_steps:
			if str(step.get("audio_path", "")).is_empty() or int(step.get("duration_ms", 0)) <= 0 or step.get("events", []).is_empty():
				return "教学段落不完整"
			if str(step.get("audio_sha256", "")).length() != 64: return "教学音频缺少校验"
			var step_ids: Dictionary = {}
			var previous_step_time := -1
			for event: Dictionary in step.events:
				var event_id := str(event.get("id", ""))
				var event_time := int(event.get("time_ms", -1))
				var event_end := int(event.get("end_ms", -1))
				var event_kind := str(event.get("kind", ""))
				if event_id.is_empty() or step_ids.has(event_id) or event_time < previous_step_time: return "教学事件编号或顺序无效"
				if event_time < 0 or event_end < event_time or event_end >= int(step.duration_ms): return "教学事件超出段落"
				if event_kind not in ["tap", "hold", "switch", "rest"] or int(event.get("direction", 0)) not in [-1, 0, 1]: return "教学动作无效"
				if int(event.get("cue_ms", -1)) < 0 or (event_kind in ["hold", "rest"] and event_end <= event_time): return "教学提示或时值无效"
				step_ids[event_id] = true
				previous_step_time = event_time
			motion_error = validate_choreography(step.get("choreography", []), int(step.duration_ms), step_ids)
			if not motion_error.is_empty(): return motion_error
	return ""

static func validate_choreography(clips: Array, duration: int, event_ids: Dictionary) -> String:
	var clip_ids: Dictionary = {}
	for clip: Dictionary in clips:
		var id := str(clip.get("id", ""))
		if id.is_empty() or clip_ids.has(id) or str(clip.get("actor", "")).is_empty() or str(clip.get("action", "")).is_empty():
			return "演出动作标识无效"
		if int(clip.get("start_ms", -1)) < 0 or int(clip.get("end_ms", -1)) <= int(clip.start_ms) or int(clip.end_ms) > duration:
			return "演出动作超出段落"
		var linked := str(clip.get("event_id", ""))
		if not linked.is_empty() and not event_ids.has(linked): return "演出动作关联无效"
		clip_ids[id] = true
	return ""
