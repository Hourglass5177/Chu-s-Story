extends Control
class_name PauseOverlay

signal resumed

@onready var continue_button: Button = %ContinueButton

var _modal_lease: int = -1
var _interaction_suspend_lease: int = -1
var _session_generation: int = -1
var _turn_epoch: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	continue_button.pressed.connect(close_pause)
	if not TurnManager.game_finished.is_connected(_on_game_finished):
		TurnManager.game_finished.connect(_on_game_finished)
	hide()


func can_open() -> bool:
	# BtnPause 与 BtnClose 位于同一 HUD 层级。二级弹窗是否拦截点击由它们自己的
	# 全屏遮罩自然决定；这里不能用“存在模态”作为拒绝条件，因为地图选点同样
	# 持有模态租约，却没有遮罩，玩家仍应能够暂停。
	return TurnManager.GameOn \
		and TurnManager.get_game_result() == null \
		and not visible


func open_pause() -> bool:
	if not can_open():
		return false
	_session_generation = TurnManager.get_session_generation()
	_turn_epoch = TurnManager.get_turn_epoch()
	_interaction_suspend_lease = InteractionCoordinator.suspend_active(&"pause_menu")
	_modal_lease = TurnManager.acquire_modal(
		&"pause_menu",
		TurnManager.ModalResumePolicy.RESUME_REMAINING,
		true
	)
	if _modal_lease < 0:
		if _interaction_suspend_lease >= 0:
			InteractionCoordinator.resume_active(_interaction_suspend_lease)
		_clear_runtime_state()
		return false
	show()
	continue_button.call_deferred(&"grab_focus")
	return true


func close_pause() -> bool:
	if not visible:
		return false
	hide()
	var same_context: bool = (
		_session_generation == TurnManager.get_session_generation()
		and _turn_epoch == TurnManager.get_turn_epoch()
	)
	if _modal_lease >= 0 and same_context:
		TurnManager.release_modal(_modal_lease)
	if _interaction_suspend_lease >= 0:
		InteractionCoordinator.resume_active(_interaction_suspend_lease)
	_clear_runtime_state()
	resumed.emit()
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close_pause()
		get_viewport().set_input_as_handled()
		return
	# 暂停层是全屏模态，未消费的键盘与手柄输入不能穿透到棋盘。
	get_viewport().set_input_as_handled()


func _on_game_finished(_result: GameResult) -> void:
	if not visible:
		return
	# 终局已经接管树暂停并失效化全部模态租约，旧暂停层只负责退场。
	hide()
	_clear_runtime_state()


func _exit_tree() -> void:
	if TurnManager.game_finished.is_connected(_on_game_finished):
		TurnManager.game_finished.disconnect(_on_game_finished)
	if visible:
		close_pause()


func _clear_runtime_state() -> void:
	_modal_lease = -1
	_interaction_suspend_lease = -1
	_session_generation = -1
	_turn_epoch = -1
