class_name PrivateDecisionHandoff
extends CanvasLayer

signal accepted
var _modal: int = -1
var _suspension: int = -1
var _session: int = -1
var _accepted: bool = false

static func needed() -> bool:
	if GameManager.is_headless_simulation() or not TurnManager.GameOn: return false
	var humans := 0
	for player: PlayerClass in TurnManager.players:
		if not player.is_bot: humans += 1
	return humans > 1

func wait_for_player(player_name: String) -> void:
	add_to_group("PRIVATE_DECISION_HANDOFF")
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_session = TurnManager.get_session_generation()
	var interaction_id := int(InteractionCoordinator.get_active_snapshot().get("interaction_id", -1))
	accepted.connect(func(): _accepted = true, CONNECT_ONE_SHOT)
	_suspension = InteractionCoordinator.suspend_active(&"human_handoff")
	_modal = TurnManager.acquire_modal(&"human_handoff", TurnManager.ModalResumePolicy.RESUME_REMAINING, true)
	var cover := ColorRect.new()
	cover.color = Color("201c22")
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(cover)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 28)
	center.add_child(column)
	var label := Label.new()
	label.text = "请将操作交给 %s" % player_name
	label.add_theme_font_size_override("font_size", 46)
	column.add_child(label)
	var button := Button.new()
	button.name = "AcceptHandoff"
	button.text = "我已接手，显示选择"
	button.add_theme_font_size_override("font_size", 34)
	button.custom_minimum_size = Vector2(480, 90)
	button.pressed.connect(func(): accepted.emit())
	column.add_child(button)
	button.grab_focus()
	while not _accepted and _session == TurnManager.get_session_generation() and int(InteractionCoordinator.get_active_snapshot().get("interaction_id", -1)) == interaction_id:
		await get_tree().process_frame
	_release()
	hide()
	queue_free()

func _release() -> void:
	if _session == TurnManager.get_session_generation():
		if _modal >= 0: TurnManager.release_modal(_modal)
		if _suspension >= 0: InteractionCoordinator.resume_active(_suspension)
	_modal = -1
	_suspension = -1

func _exit_tree() -> void:
	_release()
