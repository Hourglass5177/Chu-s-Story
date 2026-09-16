extends Node

## 只监听表现/事务结果，不改变规则状态或消耗游戏随机数。
signal cue_played(cue: StringName)
const BUS := &"BoardSFX"
const CUES := {
	&"confirm": [1, -9.0, 120], &"back": [2, -9.0, 150],
	&"invalid": [6, -6.0, 350], &"page": [2, -11.0, 200],
	&"dice_roll": [3, -6.0, 500], &"dice_land": [4, -3.0, 200],
	&"card": [3, -6.0, 300], &"trade": [6, -3.0, 350],
	&"move": [2, -10.0, 180], &"turn": [7, -4.0, 600],
	&"action": [5, -6.0, 500], &"warning": [8, -4.0, 1200],
	&"recover": [7, -5.0, 500], &"event": [5, -6.0, 500],
	&"response": [6, -6.0, 350], &"achievement": [9, -4.0, 600],
	&"result": [10, -3.0, 2000], &"eliminate": [9, -5.0, 600],
	&"technical": [9, -7.0, 800],
}
var _scopes: Dictionary[int, WeakRef] = {}
var _streams: Dictionary[StringName, AudioStream] = {}
var _voices: Array[AudioStreamPlayer] = []
var _last: Dictionary[StringName, int] = {}
var _rng := RandomNumberGenerator.new()
var _pending: StringName = &""
var _pending_gain := 0.0
var _pending_is_bot := false
var _pending_priority := -1
var _queued := false
var _last_bot_ms := -10000
var _warning_played := false
var _return_cue: StringName = &""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	get_tree().node_added.connect(_on_node_added)
	ResourceManager.card_hand_visual_requested.connect(_on_card)
	ResourceManager.food_purchased.connect(func(p, _card, _price): request(&"trade", p))
	ResourceManager.work_completed.connect(func(p, _turns, _income): request(&"trade", p))
	ResourceManager.energy_changed.connect(_on_energy)
	MarketManager.transaction_completed.connect(func(p, _card, _kind, _amount): request(&"trade", p))
	FoodManager.food_resolution_finished.connect(_on_food)
	AchievementManager.achievement_claimed.connect(func(p, _card): request(&"achievement", p))
	EventManager.event_revealed.connect(func(p, _card): request(&"event", p))
	EventManager.effect_response_resolved.connect(func(_kind, _response, p, _target): request(&"response", p))
	TurnManager.turn_start.connect(_on_turn)
	TurnManager.phase_changed.connect(_on_phase)
	TurnManager.player_eliminated.connect(func(p, _turn): request(&"eliminate", p))
	TurnManager.game_finished.connect(func(_result): request(&"result"))
	HeritageTaskManager.attempt_finished.connect(_on_inheritance_result)


func attach_scene(scene: Node) -> void:
	if DisplayServer.get_name() == "headless" or GameManager.is_headless_simulation(): return
	var id := scene.get_instance_id()
	if _scopes.has(id): return
	_scopes[id] = weakref(scene)
	scene.tree_exited.connect(_detach_scene.bind(id), CONNECT_ONE_SHOT)
	if _voices.is_empty():
		var bus := AudioServer.get_bus_index(BUS)
		if bus < 0:
			AudioServer.add_bus()
			bus = AudioServer.bus_count - 1
			AudioServer.set_bus_name(bus, BUS)
			AudioServer.set_bus_send(bus, &"Master")
			AudioServer.set_bus_volume_db(bus, -5.0)
		Settings.apply_audio()
		for cue: StringName in CUES:
			_streams[cue] = load("res://Audio/SFX/%s.wav" % cue)
		for index in range(4):
			var voice := AudioStreamPlayer.new()
			voice.bus = BUS
			add_child(voice)
			_voices.append(voice)
	_watch_tree(scene)


func _detach_scene(id: int) -> void:
	_scopes.erase(id)
	if not _scopes.is_empty(): return
	_pending = &""
	_pending_priority = -1
	_last.clear()
	_return_cue = &""
	for voice in _voices: voice.stop()


func _on_node_added(node: Node) -> void:
	if _scopes.is_empty(): return
	if node is BaseButton or node is PlayerClass or _is_detail_panel(node):
		_watch_weak_node.call_deferred(weakref(node))


func _watch_weak_node(reference: WeakRef) -> void:
	var node := reference.get_ref() as Node
	if node != null: _watch_node(node)


func _watch_tree(node: Node) -> void:
	_watch_node(node)
	for child in node.get_children(): _watch_tree(child)


func _watch_node(node: Node) -> void:
	if not is_instance_valid(node) or not _belongs_to_board(node): return
	if node.has_meta(&"board_sfx_bound"): return
	if node is BaseButton:
		node.set_meta(&"board_sfx_bound", true)
		node.pressed.connect(_on_button.bind(node))
	elif node is PlayerClass:
		node.set_meta(&"board_sfx_bound", true)
		node.movement_completed.connect(func(_pos): request(&"move", node))
	elif _is_detail_panel(node):
		node.set_meta(&"board_sfx_bound", true)
		node.visibility_changed.connect(func():
			if node.is_visible_in_tree(): request(&"page"))


func _is_detail_panel(node: Node) -> bool:
	return node is 非遗详情弹窗 or node is ProfessionDetailPanel or node is AchievementDetailPanel or node is ScoreDetailPanel or node is FoodBackpackPanel


func _belongs_to_board(node: Node) -> bool:
	var ancestor := node
	while is_instance_valid(ancestor):
		if ancestor is HeritageTaskHost: return false
		if _scopes.has(ancestor.get_instance_id()): return true
		ancestor = ancestor.get_parent()
	return false


func _on_button(button: BaseButton) -> void:
	# pressed 前面的业务槽可能已经隐藏当前页；不能因此吞掉本次真实点击。
	if not is_instance_valid(button) or button.disabled: return
	var ancestor: Node = button
	while ancestor != null:
		if ancestor is MainMenu and not ancestor._preferences.ui_sound_enabled: return
		ancestor = ancestor.get_parent()
	var caption: String = button.text if button is Button else String(button.name)
	var cue: StringName = &"confirm"
	for word in ["返回", "取消", "关闭", "Back", "Close", "Cancel"]:
		if caption.contains(word): cue = &"back"
	request(cue)


func request(cue: StringName, player: PlayerClass = null) -> void:
	if _scopes.is_empty() or not CUES.has(cue) or BoardMusic.is_minigame_active(): return
	var now := Time.get_ticks_msec()
	if now - int(_last.get(cue, -10000)) < int(CUES[cue][2]): return
	var gain := 0.0
	var is_bot := is_instance_valid(player) and player.is_bot
	if is_bot:
		if cue in [&"turn", &"action", &"warning"] or now - _last_bot_ms < 450: return
		gain = -5.0
	var priority: int = CUES[cue][0]
	if priority >= _pending_priority:
		_pending = cue
		_pending_gain = gain
		_pending_is_bot = is_bot
		_pending_priority = priority
	if not _queued:
		_queued = true
		_flush.call_deferred()


func _flush() -> void:
	_queued = false
	var cue := _pending
	var gain := _pending_gain
	var is_bot := _pending_is_bot
	_pending = &""
	_pending_priority = -1
	if cue == &"" or _scopes.is_empty() or BoardMusic.is_minigame_active(): return
	var chosen: AudioStreamPlayer
	for voice in _voices:
		if not voice.playing:
			chosen = voice
			break
	if chosen == null:
		for voice in _voices:
			if int(voice.get_meta(&"priority", 0)) < int(CUES[cue][0]):
				chosen = voice
				break
	if chosen == null: return
	chosen.stop()
	chosen.stream_paused = false
	chosen.stream = _streams[cue]
	chosen.volume_db = float(CUES[cue][1]) + gain
	chosen.pitch_scale = _rng.randf_range(0.97, 1.03) if cue in [&"move", &"card", &"dice_land", &"trade"] else 1.0
	chosen.set_meta(&"cue", cue)
	chosen.set_meta(&"priority", CUES[cue][0])
	chosen.play()
	_last[cue] = Time.get_ticks_msec()
	if is_bot: _last_bot_ms = Time.get_ticks_msec()
	cue_played.emit(cue)


func stop_cue(cue: StringName) -> void:
	for voice in _voices:
		if voice.get_meta(&"cue", &"") == cue: voice.stop()
	if _pending == cue:
		_pending = &""
		_pending_priority = -1


func _process(_delta: float) -> void:
	if _scopes.is_empty(): return
	if _return_cue != &"" and not BoardMusic.is_minigame_active():
		request(_return_cue)
		_return_cue = &""
	for voice in _voices:
		if BoardMusic.is_minigame_active(): voice.stop()
		elif voice.get_meta(&"cue", &"") in [&"dice_roll", &"move"]:
			voice.stream_paused = get_tree().paused
	if _warning_played or not TurnManager.GameOn or get_tree().paused or TurnManager.is_modal_resolution_active() or GameManager.is_tutorial_session(): return
	if TurnManager.now_phase not in [TurnManager.TurnPhase.MOVING, TurnManager.TurnPhase.ACTION]: return
	var timer: Timer = TurnManager.turn_timer
	if timer.is_stopped() or timer.time_left <= 0 or timer.time_left > 5: return
	_warning_played = true
	request(&"warning", _current_player())


func _current_player() -> PlayerClass:
	var index: int = TurnManager.now_player_index
	return TurnManager.players[index] if index >= 0 and index < TurnManager.players.size() else null


func _on_turn(_index: int) -> void:
	_warning_played = false
	request(&"turn", _current_player())


func _on_phase(phase: int) -> void:
	_warning_played = false
	if phase == TurnManager.TurnPhase.ACTION: request(&"action", _current_player())


func _on_card(kind: int, player: PlayerClass, _card: Resource, _other: PlayerClass, _reveal: bool) -> void:
	if kind == ResourceManager.CardHandVisualKind.获得: request(&"card", player)


func _on_food(player: PlayerClass, result: FoodResolutionResult) -> void:
	if result.success and result.effect_applied: request(&"recover", player)
	elif not result.success: request(&"invalid", player)


func _on_energy(player: PlayerClass, previous: int, current: int, reason: String) -> void:
	if current > previous and reason == "事件：妙手回春": request(&"recover", player)


func _on_inheritance_result(_attempt: HeritageTaskAttempt, result: HeritageTaskResult) -> void:
	if result.status == HeritageTaskResult.Status.TECHNICAL_ERROR:
		_return_cue = &"technical"
