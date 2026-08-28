extends HeritageTaskBase

enum Stage {
	LISTENING,
	COUNTDOWN,
	RECORDING,
	SCORING,
}

const COUNTDOWN_SECONDS: float = 2.0
const RECORD_SECONDS: float = 13.65
const FIRST_LINE_DURATION: float = 5.0
const VIDEO_LINE_ONE_START: float = 0.4
const VIDEO_LINE_TWO_START: float = 5.4
const FALLBACK_VIDEO_PATH := "res://arts/非遗媒体资源/数字版/黄梅戏-女驸马-传承任务-v1.ogv"

@onready var reference_video: VideoStreamPlayer = %ReferenceVideo
@onready var lyrics_label: RichTextLabel = %Lyrics
@onready var stage_label: Label = %StageLabel

var _stage: Stage = Stage.LISTENING
var _stage_time: float = 0.0
var _scorer: VocalScorer = null
var _technical_message: String = ""


func on_task_started() -> void:
	_stage = Stage.LISTENING
	_stage_time = 0.0
	_scorer = context.get_service(&"vocal_scorer") as VocalScorer
	if _scorer == null or not _scorer.is_available():
		var reason: StringName = (
			_scorer.get_unavailable_reason()
			if _scorer != null
			else &"vocal_scorer_missing"
		)
		complete_technical_error(reason, "麦克风或演唱评分模块暂不可用")
		return
	var video_path := String(context.metadata.get(&"reference_video_path", FALLBACK_VIDEO_PATH))
	var video_stream := load(video_path) as VideoStream
	if video_stream == null:
		complete_technical_error(&"reference_video_missing", "示范唱段无法载入")
		return
	reference_video.stream = video_stream
	if not reference_video.finished.is_connected(_on_reference_finished):
		reference_video.finished.connect(_on_reference_finished)
	reference_video.paused = false
	reference_video.play()
	stage_label.text = "先听完整示范"
	_update_lyrics(0.0, true)
	queue_redraw()


func task_tick(delta: float) -> void:
	match _stage:
		Stage.LISTENING:
			_stage_time += delta
			var listen_position := reference_video.stream_position
			var listen_length := maxf(reference_video.get_stream_length(), 0.1)
			set_progress(minf(listen_position / listen_length, 1.0) * 0.35)
			_update_lyrics(listen_position, true)
			if _stage_time >= listen_length + 0.5:
				_enter_countdown()
		Stage.COUNTDOWN:
			_stage_time += delta
			set_progress(0.35 + minf(_stage_time / COUNTDOWN_SECONDS, 1.0) * 0.05)
			stage_label.text = "%d" % maxi(1, ceili(COUNTDOWN_SECONDS - _stage_time))
			if _stage_time >= COUNTDOWN_SECONDS:
				_begin_recording()
		Stage.RECORDING:
			_stage_time += delta
			set_progress(0.40 + minf(_stage_time / RECORD_SECONDS, 1.0) * 0.50)
			stage_label.text = "正在录唱 · 第%d句" % (1 if _stage_time < FIRST_LINE_DURATION else 2)
			_update_lyrics(_stage_time, false)
			if _stage_time >= RECORD_SECONDS:
				_finish_recording()
		Stage.SCORING:
			_stage_time += delta
			set_progress(0.90)
			stage_label.text = "正在本地评分"
		_:
			complete_technical_error(&"invalid_stage", "录唱流程发生错误")


func on_task_finished(_result: HeritageTaskResult) -> void:
	reference_video.stop()
	if _scorer != null:
		_scorer.cancel_capture()


func on_suspension_changed(suspended: bool) -> void:
	if _stage == Stage.LISTENING:
		reference_video.paused = suspended
	if _stage == Stage.RECORDING and _scorer != null:
		_scorer.set_capture_paused(suspended)


func on_time_expired() -> void:
	if _stage == Stage.SCORING:
		complete_technical_error(&"scoring_timeout", "演唱评分超时，请检查评分模块")
	else:
		complete_failure(&"recording_incomplete", "唱句没有完整录下")


func _enter_countdown() -> void:
	if _stage != Stage.LISTENING:
		return
	_stage = Stage.COUNTDOWN
	_stage_time = 0.0
	reference_video.stop()
	reference_video.hide()
	stage_label.text = "准备录唱"
	pulse_feedback(&"countdown")


func _on_reference_finished() -> void:
	_enter_countdown()


func _begin_recording() -> void:
	if not is_input_active() or _scorer == null:
		return
	# 设备与评分模块已在任务真正进入前预检；录音开始时仍由
	# begin_capture() 处理运行期间设备被移除等瞬时故障。
	if not _scorer.scoring_completed.is_connected(_on_scoring_completed):
		_scorer.scoring_completed.connect(_on_scoring_completed, CONNECT_ONE_SHOT)
	var start_error: Error = _scorer.begin_capture(task_id, RECORD_SECONDS)
	if start_error != OK:
		complete_technical_error(&"capture_start_failed", "无法开始录音，请检查麦克风权限")
		return
	_stage = Stage.RECORDING
	_stage_time = 0.0
	stage_label.text = "正在录唱 · 第1句"
	pulse_feedback(&"recording")


func _finish_recording() -> void:
	_stage = Stage.SCORING
	_stage_time = 0.0
	var score_error: Error = _scorer.finish_capture_and_score()
	if score_error != OK:
		complete_technical_error(&"scoring_start_failed", "录音无法送入评分模块")


func _on_scoring_completed(payload: Dictionary) -> void:
	if not is_input_active() or _stage != Stage.SCORING:
		return
	if not bool(payload.get("ok", false)):
		complete_technical_error(
			StringName(payload.get("reason", "scoring_failed")),
			str(payload.get("message", "这段录音暂时无法判定"))
		)
		return
	var score: float = float(payload.get("score", 0.0))
	var metrics: Dictionary = payload.duplicate(true)
	metrics["score"] = score
	if bool(payload.get("passed", score >= 60.0)):
		set_progress(1.0)
		complete_success(metrics, "两句都接上了")
	else:
		complete_failure(
			&"vocal_similarity_low",
			str(payload.get("feedback", "再听清收束拍的位置")),
			metrics
		)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.16, 0.08, 0.12, 1.0), true)
	var center_y: float = size.y * 0.48
	var left: float = size.x * 0.10
	var width: float = size.x * 0.80
	for index: int in 96:
		var x: float = left + width * float(index) / 95.0
		var wave: float = sin(float(index) * 0.27) * 34.0 + sin(float(index) * 0.08) * 18.0
		draw_circle(Vector2(x, center_y + wave), 3.0, Color(0.96, 0.72, 0.28, 0.82))
	if _stage == Stage.RECORDING:
		draw_circle(Vector2(size.x * 0.5, size.y * 0.72), 14.0 + sin(_stage_time * 6.0) * 3.0, Color(0.88, 0.18, 0.16, 1.0))


func _update_lyrics(position: float, video_timeline: bool) -> void:
	var second_line := position >= (VIDEO_LINE_TWO_START if video_timeline else FIRST_LINE_DURATION)
	if second_line:
		lyrics_label.text = "[center][color=#bda47d]为救李郎离家园[/color]　／　[color=#ffd66b][b]谁料皇榜中状元[/b][/color][/center]"
	else:
		lyrics_label.text = "[center][color=#ffd66b][b]为救李郎离家园[/b][/color]　／　[color=#bda47d]谁料皇榜中状元[/color][/center]"
