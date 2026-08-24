extends Control
class_name ProfessionSkillToast

@onready var panel: PanelContainer = $Panel
@onready var portrait: TextureRect = $Panel/Row/PortraitShell/Portrait
@onready var title: Label = $Panel/Row/Text/Title
@onready var message_label: Label = $Panel/Row/Text/Message

var _queue: Array[Dictionary] = []
var _playing := false
var _active_tween: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()


func enqueue(player: PlayerClass, profession_id: StringName, message: String) -> void:
	if player == null or message.is_empty():
		return
	var definition: ProfessionDefinition = ProfessionManager.get_definition_by_id(profession_id)
	_queue.append({
		"portrait": player.立绘精一,
		"title": definition.profession_name if definition != null else PlayerClass.PlayerCharacter.find_key(player.player_types),
		"message": message,
	})
	if not _playing:
		_play_next()


func reset_toast() -> void:
	_queue.clear()
	_playing = false
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	_active_tween = null
	hide()


func _play_next() -> void:
	if _queue.is_empty():
		_playing = false
		hide()
		return
	_playing = true
	var item: Dictionary = _queue.pop_front()
	portrait.texture = item["portrait"] as Texture2D
	title.text = str(item["title"])
	message_label.text = str(item["message"])
	panel.modulate = Color(1, 1, 1, 0)
	panel.position.y = 28.0
	show()
	_active_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_active_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(panel, "modulate:a", 1.0, 0.16)
	_active_tween.parallel().tween_property(panel, "position:y", 0.0, 0.22)
	_active_tween.tween_interval(1.25)
	_active_tween.set_ease(Tween.EASE_IN)
	_active_tween.tween_property(panel, "modulate:a", 0.0, 0.18)
	_active_tween.parallel().tween_property(panel, "position:y", -18.0, 0.18)
	_active_tween.tween_callback(_play_next)
