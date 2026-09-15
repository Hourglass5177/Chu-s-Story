class_name HeritageBeatCalibration
extends PanelContainer

signal closed
const FIRST_BEAT_MS := 700
const BEAT_MS := 700
const WARMUP := 2
const SAMPLE_COUNT := 16
var player: HeritageMusicClock
var origin: int = 0 # Retained for diagnostic compatibility, never the hit clock.
var next_beat: int = 0
var samples: Array[int] = []
var prompt: Label
var saved: bool = false
var finished: bool = false
var last_sampled_beat: int = -1
var device_key: String = ""
var result: Dictionary = {}
var _suspension_reasons: Dictionary = {}
var _paused_at: int = -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	add_child(box)
	prompt = Label.new()
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(prompt)
	var tap := Button.new()
	tap.text = "听到短音就按"
	tap.custom_minimum_size.y = 48
	tap.pressed.connect(_tap)
	box.add_child(tap)
	var retry := Button.new()
	retry.text = "重新校准"
	retry.custom_minimum_size.y = 48
	retry.pressed.connect(_restart)
	box.add_child(retry)
	var back := Button.new()
	back.text = "返回"
	back.custom_minimum_size.y = 48
	back.pressed.connect(func() -> void:
		if is_instance_valid(player): player.stop()
		closed.emit())
	box.add_child(back)
	player = HeritageMusicClock.new()
	add_child(player)
	_restart()
	tap.grab_focus()

func _restart() -> void:
	samples.clear()
	result.clear()
	saved = false
	finished = false
	next_beat = 0
	last_sampled_beat = -1
	origin = Time.get_ticks_msec()
	prompt.text = "先听两拍，再跟十六拍"
	var stream := load("res://InheritanceTasks/Audio/rhythm-v2/calibration.ogg") as AudioStream
	if stream == null:
		finished = true
		prompt.text = "校准声音未就绪"
		return
	player.begin(stream)
	player.freeze(not _suspension_reasons.is_empty())

func _process(_delta: float) -> void:
	if finished or not _suspension_reasons.is_empty() or not is_instance_valid(player): return
	var ms := roundi(player.seconds() * 1000.0)
	next_beat = maxi(0, (ms - FIRST_BEAT_MS) / BEAT_MS + 1)
	if ms > FIRST_BEAT_MS + (WARMUP + SAMPLE_COUNT) * BEAT_MS + 300:
		finished = true
		prompt.text = "还没跟满十六拍，再试一次"
		player.stop()

func _tap() -> void:
	if finished or not _suspension_reasons.is_empty() or not is_instance_valid(player): return
	var ms := roundi(player.seconds() * 1000.0)
	var beat := roundi(float(ms - FIRST_BEAT_MS) / BEAT_MS)
	if beat < WARMUP or beat >= WARMUP + SAMPLE_COUNT or beat <= last_sampled_beat: return
	var error := ms - FIRST_BEAT_MS - beat * BEAT_MS
	if absi(error) > 300: return
	last_sampled_beat = beat
	samples.append(error)
	prompt.text = "已跟 %d / %d 拍" % [samples.size(), SAMPLE_COUNT]
	if samples.size() < SAMPLE_COUNT: return
	result = summarize(samples)
	finished = true
	player.stop()
	if not bool(result.stable):
		prompt.text = "这次节拍不太稳定，重新试一次"
		return
	HeritageMinigamePreferences.save_offset(int(result.offset_ms), device_key)
	saved = true
	prompt.text = "已保存 · 偏移 %d 毫秒\n波动 %d 毫秒" % [result.offset_ms, result.spread_ms]

static func summarize(values: Array[int]) -> Dictionary:
	if values.size() < SAMPLE_COUNT: return {"stable": false, "offset_ms": 0, "spread_ms": 0}
	var ordered := values.duplicate()
	ordered.sort()
	var median: int = (int(ordered[7]) + int(ordered[8])) / 2
	var deviations: Array[int] = []
	for value: int in ordered: deviations.append(absi(value - median))
	deviations.sort()
	var spread := (deviations[7] + deviations[8]) / 2
	return {"stable": spread <= 65, "offset_ms": clampi(median, -300, 300), "spread_ms": spread}

func set_suspended(value: bool, reason: StringName = &"host") -> void:
	var was_paused := not _suspension_reasons.is_empty()
	if value: _suspension_reasons[reason] = true
	else: _suspension_reasons.erase(reason)
	var now_paused := not _suspension_reasons.is_empty()
	if was_paused == now_paused: return
	if now_paused: _paused_at = Time.get_ticks_msec()
	else:
		origin += maxi(0, Time.get_ticks_msec() - _paused_at)
		_paused_at = -1
	if is_instance_valid(player): player.freeze(now_paused)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT: set_suspended(true, &"window_focus")
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_IN: set_suspended(false, &"window_focus")
