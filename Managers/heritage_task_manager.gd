extends Node

signal attempt_started(attempt: HeritageTaskAttempt)
signal attempt_finished(attempt: HeritageTaskAttempt, result: HeritageTaskResult)
signal inheritance_completed(player: PlayerClass, card: 非遗牌, task_id: StringName)
signal inheritance_state_changed(player: PlayerClass, card: 非遗牌, inherited: bool)

const DEFINITION_DIR: String = "res://InheritanceTasks/Definitions"
const TASK_ENERGY_COST: int = 1

var _definitions: Dictionary[StringName, HeritageTaskDefinition] = {}
var _inherited_by_task_id: Dictionary[StringName, bool] = {}
var _attempted_turn_by_task_id: Dictionary[StringName, Dictionary] = {}
var _active_attempts: Dictionary[int, HeritageTaskAttempt] = {}
var _players: Array[PlayerClass] = []
var _attempt_sequence: int = 0


func _ready() -> void:
	reload_definitions()


func reload_definitions() -> void:
	_definitions.clear()
	var files: PackedStringArray = DirAccess.get_files_at(DEFINITION_DIR)
	files.sort()
	for file_name: String in files:
		if not file_name.ends_with(".tres") and not file_name.ends_with(".tres.remap"):
			continue
		var actual_file := file_name.trim_suffix(".remap")
		var resource := ResourceLoader.load(DEFINITION_DIR.path_join(actual_file))
		var definition := resource as HeritageTaskDefinition
		if definition == null or not definition.is_valid_definition():
			push_error("HeritageTaskManager: 无效传承任务定义：%s" % actual_file)
			continue
		if _definitions.has(definition.task_id):
			push_error("HeritageTaskManager: 重复的传承任务 ID：%s" % definition.task_id)
			continue
		_definitions[definition.task_id] = definition


func get_definition(card_or_task_id: Variant) -> HeritageTaskDefinition:
	var task_id := _resolve_task_id(card_or_task_id)
	return _definitions.get(task_id) as HeritageTaskDefinition


func is_inherited(card: 非遗牌) -> bool:
	if card == null or card.category != 非遗牌.CardCategory.国家级非遗:
		return false
	var task_id := _resolve_task_id(card)
	return not task_id.is_empty() and bool(_inherited_by_task_id.get(task_id, false))


func is_effective_card(card: 非遗牌) -> bool:
	if card == null:
		return false
	if card.category != 非遗牌.CardCategory.国家级非遗:
		return true
	return is_inherited(card)


func get_display_score(card: 非遗牌) -> Variant:
	if card == null:
		return 0
	if card.category == 非遗牌.CardCategory.国家级非遗 and not is_inherited(card):
		return "?"
	return card.base_score


func get_attempt_check(player: PlayerClass, card: 非遗牌) -> HeritageTaskUseCheck:
	if player == null or not is_instance_valid(player):
		return HeritageTaskUseCheck.deny(&"invalid_player", "玩家无效。")
	if not _players.has(player):
		return HeritageTaskUseCheck.deny(&"unregistered_player", "玩家不属于当前对局。")
	if card == null or card.category != 非遗牌.CardCategory.国家级非遗:
		return HeritageTaskUseCheck.deny(&"not_national_heritage", "这张牌没有传承任务。")
	var task_id := _resolve_task_id(card)
	if task_id.is_empty():
		return HeritageTaskUseCheck.deny(&"missing_task_id", "传承任务尚未配置。")
	if get_definition(task_id) == null:
		return HeritageTaskUseCheck.deny(&"missing_definition", "传承任务资源缺失。")
	if is_inherited(card):
		return HeritageTaskUseCheck.deny(&"already_inherited", "这张牌已完成传承。")
	if not player.非遗牌手牌.has(card):
		return HeritageTaskUseCheck.deny(&"card_not_owned", "你没有这张非遗牌。")
	if not player.alive or not player.onTurn:
		return HeritageTaskUseCheck.deny(&"player_unavailable", "当前不能进行传承任务。")
	if not TurnManager.GameOn \
			or TurnManager.now_phase != TurnManager.TurnPhase.ACTION \
			or TurnManager.now_player_index < 0 \
			or TurnManager.now_player_index >= TurnManager.players.size() \
			or TurnManager.players[TurnManager.now_player_index] != player:
		return HeritageTaskUseCheck.deny(&"not_action_phase", "仅可在自己的行动阶段进行。")
	if player.current_energy < TASK_ENERGY_COST:
		return HeritageTaskUseCheck.deny(&"insufficient_energy", "精力不足。")
	if _was_attempted_this_turn(task_id):
		return HeritageTaskUseCheck.deny(&"already_attempted_this_turn", "本行动阶段已尝试过这项任务。")
	if not InteractionCoordinator.get_active_snapshot().is_empty():
		return HeritageTaskUseCheck.deny(&"interaction_busy", "请先完成当前操作。")
	return HeritageTaskUseCheck.allow()


func begin_attempt(player: PlayerClass, card: 非遗牌) -> HeritageTaskAttempt:
	var check := get_attempt_check(player, card)
	if check == null or not check.allowed:
		return null
	var task_id := _resolve_task_id(card)
	var metadata := {
		&"task_id": task_id,
		&"player": player,
		&"card": card,
	}
	var ticket := InteractionCoordinator.begin_interaction(
		&"heritage_task",
		0.0,
		Callable(),
		TurnManager.ModalResumePolicy.RESUME_REMAINING,
		false,
		metadata
	)
	if ticket == null:
		return null

	_attempt_sequence += 1
	var attempt := HeritageTaskAttempt.new()
	attempt.attempt_id = _attempt_sequence
	attempt.task_id = task_id
	attempt.player = player
	attempt.card = card
	attempt.session_generation = TurnManager.get_session_generation()
	attempt.turn_epoch = TurnManager.get_turn_epoch()
	attempt.interaction_ticket = ticket
	attempt.energy_cost = TASK_ENERGY_COST
	attempt.energy_paid = false
	attempt.state = HeritageTaskAttempt.State.RUNNING

	_attempted_turn_by_task_id[task_id] = {
		&"session_generation": attempt.session_generation,
		&"turn_epoch": attempt.turn_epoch,
	}
	_active_attempts[attempt.attempt_id] = attempt
	if not ResourceManager.modify_energy(player, -TASK_ENERGY_COST, "传承任务：%s" % card.card_name, true):
		_attempted_turn_by_task_id.erase(task_id)
		_active_attempts.erase(attempt.attempt_id)
		attempt.state = HeritageTaskAttempt.State.ROLLED_BACK
		InteractionCoordinator.cancel(ticket.interaction_id, &"energy_payment_failed")
		_consume_ticket(ticket)
		return null
	attempt.energy_paid = true
	attempt_started.emit(attempt)
	return attempt


func finish_attempt(attempt: HeritageTaskAttempt, result: HeritageTaskResult) -> bool:
	if not _is_current_active_attempt(attempt):
		return false
	if result == null:
		result = HeritageTaskResult.technical_error(
			attempt.task_id,
			&"invalid_result",
			"任务返回了无效结果"
		)
	elif not result.task_id.is_empty() and result.task_id != attempt.task_id:
		result = HeritageTaskResult.technical_error(
			attempt.task_id,
			&"result_task_mismatch",
			"任务返回结果与当前任务不匹配"
		)
	if not _attempt_gameplay_context_is_current(attempt):
		_cleanup_stale_attempt(attempt)
		return false
	result.task_id = attempt.task_id

	var ticket := attempt.interaction_ticket as InteractionTicket
	if ticket == null:
		return false
	var interaction_finished_ok := false
	if result.status == HeritageTaskResult.Status.CANCELLED:
		interaction_finished_ok = InteractionCoordinator.cancel(ticket.interaction_id, result.reason)
	else:
		interaction_finished_ok = InteractionCoordinator.submit(ticket.interaction_id, result)
	if not interaction_finished_ok:
		_rollback_orphaned_attempt(attempt, &"interaction_lost")
		return false

	_active_attempts.erase(attempt.attempt_id)
	var should_rollback := result.status == HeritageTaskResult.Status.TECHNICAL_ERROR \
		or (result.status == HeritageTaskResult.Status.CANCELLED and result.reason != &"session_reset")
	if should_rollback:
		_rollback_attempt(attempt)
	else:
		attempt.state = HeritageTaskAttempt.State.FINISHED

	var newly_inherited := false
	if result.status == HeritageTaskResult.Status.SUCCESS \
			and not bool(_inherited_by_task_id.get(attempt.task_id, false)):
		_inherited_by_task_id[attempt.task_id] = true
		newly_inherited = true

	_consume_ticket(ticket)
	if newly_inherited:
		var inherited_player := attempt.player as PlayerClass
		var inherited_card := attempt.card as 非遗牌
		ResourceManager.refresh_feiyi_effective_state(inherited_player)
		inheritance_state_changed.emit(inherited_player, inherited_card, true)
		inheritance_completed.emit(inherited_player, inherited_card, attempt.task_id)
	attempt_finished.emit(attempt, result)
	return true


func abort_attempt(attempt: HeritageTaskAttempt, reason: StringName) -> bool:
	if not _is_current_active_attempt(attempt):
		return false
	var status := HeritageTaskResult.Status.CANCELLED
	if reason == &"manual_abort" or reason == &"player_cancelled":
		status = HeritageTaskResult.Status.MANUAL_ABORT
	var result := HeritageTaskResult.new(status, attempt.task_id, reason)
	return finish_attempt(attempt, result)


func reset_for_new_game(players: Array[PlayerClass]) -> void:
	_cancel_active_for_session_reset()
	_inherited_by_task_id.clear()
	_attempted_turn_by_task_id.clear()
	_players.assign(players)
	if _definitions.is_empty():
		reload_definitions()


func reset_session() -> void:
	_cancel_active_for_session_reset()
	_inherited_by_task_id.clear()
	_attempted_turn_by_task_id.clear()
	_players.clear()


func _resolve_task_id(card_or_task_id: Variant) -> StringName:
	if card_or_task_id is 非遗牌:
		return (card_or_task_id as 非遗牌).inheritance_task_id
	if card_or_task_id is StringName or card_or_task_id is String:
		return StringName(card_or_task_id)
	return &""


func _was_attempted_this_turn(task_id: StringName) -> bool:
	if not _attempted_turn_by_task_id.has(task_id):
		return false
	var record: Dictionary = _attempted_turn_by_task_id[task_id]
	return int(record.get(&"session_generation", -1)) == TurnManager.get_session_generation() \
		and int(record.get(&"turn_epoch", -1)) == TurnManager.get_turn_epoch()


func _is_current_active_attempt(attempt: HeritageTaskAttempt) -> bool:
	return attempt != null \
		and attempt.state == HeritageTaskAttempt.State.RUNNING \
		and _active_attempts.get(attempt.attempt_id) == attempt


func _attempt_context_is_current(attempt: HeritageTaskAttempt) -> bool:
	return attempt.session_generation == TurnManager.get_session_generation() \
		and attempt.turn_epoch == TurnManager.get_turn_epoch()


func _attempt_gameplay_context_is_current(attempt: HeritageTaskAttempt) -> bool:
	if not _attempt_context_is_current(attempt):
		return false
	if not is_instance_valid(attempt.player) or not is_instance_valid(attempt.card):
		return false
	if not _players.has(attempt.player):
		return false
	if not attempt.player.alive or not attempt.player.onTurn:
		return false
	if not TurnManager.GameOn or TurnManager.now_phase != TurnManager.TurnPhase.ACTION:
		return false
	if TurnManager.now_player_index < 0 or TurnManager.now_player_index >= TurnManager.players.size():
		return false
	if TurnManager.players[TurnManager.now_player_index] != attempt.player:
		return false
	return attempt.player.非遗牌手牌.has(attempt.card)


func _rollback_attempt(attempt: HeritageTaskAttempt) -> void:
	if attempt.energy_paid and is_instance_valid(attempt.player):
		ResourceManager.modify_energy(attempt.player as PlayerClass, attempt.energy_cost, "传承任务异常返还", true)
	attempt.energy_paid = false
	var record: Dictionary = _attempted_turn_by_task_id.get(attempt.task_id, {})
	if int(record.get(&"session_generation", -1)) == attempt.session_generation \
			and int(record.get(&"turn_epoch", -1)) == attempt.turn_epoch:
		_attempted_turn_by_task_id.erase(attempt.task_id)
	attempt.state = HeritageTaskAttempt.State.ROLLED_BACK


func _cleanup_stale_attempt(attempt: HeritageTaskAttempt) -> void:
	# 任务结果若越过回合或会话边界，绝不能再写入当前对局。与此同时，
	# 也不能把旧交互留在协调器中阻塞后续按钮；按技术取消回滚本次成本。
	if not _is_current_active_attempt(attempt):
		return
	_active_attempts.erase(attempt.attempt_id)
	_cancel_attempt_ticket_if_active(attempt, &"stale_context")
	_rollback_attempt(attempt)
	var ticket := attempt.interaction_ticket as InteractionTicket
	if ticket != null:
		_consume_ticket(ticket)
	var cancelled := HeritageTaskResult.new(
		HeritageTaskResult.Status.CANCELLED,
		attempt.task_id,
		&"stale_context",
		"任务已随当前回合结束"
	)
	attempt_finished.emit(attempt, cancelled)


func _rollback_orphaned_attempt(attempt: HeritageTaskAttempt, reason: StringName) -> void:
	# The coordinator may have been cancelled by a same-turn scene/UI teardown.
	# Never leave the gameplay transaction active after its input owner is gone.
	if not _is_current_active_attempt(attempt):
		return
	_active_attempts.erase(attempt.attempt_id)
	_rollback_attempt(attempt)
	var ticket := attempt.interaction_ticket as InteractionTicket
	if ticket != null:
		_consume_ticket(ticket)
	var technical := HeritageTaskResult.technical_error(
		attempt.task_id,
		reason,
		"任务交互已意外结束"
	)
	attempt_finished.emit(attempt, technical)


func _cancel_attempt_ticket_if_active(attempt: HeritageTaskAttempt, reason: StringName) -> void:
	if attempt == null or attempt.interaction_ticket == null:
		return
	var snapshot: Dictionary = InteractionCoordinator.get_active_snapshot()
	if int(snapshot.get("interaction_id", -1)) != int(attempt.interaction_ticket.interaction_id):
		return
	# Public cancel rejects stale epochs. This manager owns the active transaction,
	# so cancel_all is required to release that exact stale ticket immediately.
	InteractionCoordinator.cancel_all(reason)


func _cancel_active_for_session_reset() -> void:
	var attempts: Array[HeritageTaskAttempt] = []
	for value: Variant in _active_attempts.values():
		var active_attempt := value as HeritageTaskAttempt
		if active_attempt != null:
			attempts.append(active_attempt)
	_active_attempts.clear()
	for attempt: HeritageTaskAttempt in attempts:
		if attempt == null or attempt.state != HeritageTaskAttempt.State.RUNNING:
			continue
		attempt.state = HeritageTaskAttempt.State.FINISHED
		var result := HeritageTaskResult.new(
			HeritageTaskResult.Status.CANCELLED,
			attempt.task_id,
			&"session_reset"
		)
		var ticket := attempt.interaction_ticket as InteractionTicket
		if ticket != null:
			InteractionCoordinator.cancel(ticket.interaction_id, &"session_reset")
			_consume_ticket(ticket)
		attempt_finished.emit(attempt, result)


func _consume_ticket(ticket: InteractionTicket) -> void:
	if ticket == null:
		return
	await InteractionCoordinator.await_result(ticket)
