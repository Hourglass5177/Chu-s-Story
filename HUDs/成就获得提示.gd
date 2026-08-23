extends Control
class_name AchievementToast

signal presentation_cue_requested(cue_id: StringName)

@onready var panel: PanelContainer = $Panel
@onready var card_image: TextureRect = $Panel/Margin/Content/CardImage
@onready var name_label: Label = $Panel/Margin/Content/Text/Name
@onready var score_label: Label = $Panel/Margin/Content/Text/Score
@onready var display_timer: Timer = $DisplayTimer

var _queue: Array[Dictionary] = []
var _current: Dictionary = {}
var _tween: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	display_timer.timeout.connect(_dismiss_current)
	hide()


func enqueue(card: 成就牌, owner: PlayerClass = null) -> void:
	if card == null:
		return
	_queue.append({"card": card, "owner": owner})
	if _current.is_empty():
		_show_next()


func clear_queue() -> void:
	_queue.clear()
	_current.clear()
	display_timer.stop()
	_kill_tween()
	hide()


func _show_next() -> void:
	if _queue.is_empty():
		_current.clear()
		hide()
		return
	_current = _queue.pop_front()
	var card := _current.get("card") as 成就牌
	var owner := _current.get("owner") as PlayerClass
	card_image.texture = card.image_of_front
	name_label.text = "%s · %s" % [owner.player_name, card.card_name] if owner != null and is_instance_valid(owner) else card.card_name
	score_label.text = "+%d分" % card.score_value
	show()
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.94, 0.94)
	panel.pivot_offset = panel.size * 0.5
	_kill_tween()
	_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(panel, "modulate:a", 1.0, 0.18)
	_tween.tween_property(panel, "scale", Vector2.ONE, 0.22)
	presentation_cue_requested.emit(&"achievement_claimed")
	display_timer.start(2.2)


func _dismiss_current() -> void:
	_kill_tween()
	_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_property(panel, "modulate:a", 0.0, 0.18)
	_tween.tween_property(panel, "scale", Vector2(0.97, 0.97), 0.18)
	_tween.finished.connect(_on_dismiss_finished, CONNECT_ONE_SHOT)


func _on_dismiss_finished() -> void:
	_current.clear()
	_show_next()


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
