extends Node

## 独立的真实会话回归：不替换 FrontendSessionLauncher，也不直接加载 main_map。
## 它从首页按正式 UI 意图完成配置，经过加载页进入对局，再返回首页开启第二局。

const MAIN_MENU_SCENE: String = "res://main_menu.tscn"
const WAIT_TIMEOUT_SECONDS: float = 30.0
const REAL_POINTER_DRIVER := preload("res://tests/helpers/real_pointer_driver.gd")

var _failed: bool = false
var _pointer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pointer = REAL_POINTER_DRIVER.new(get_viewport(), get_tree())
	# 本节点是测试驱动器而不是被测场景。把 current_scene 所有权交还给
	# 后续加载的主菜单，使驱动器能跨两次正式场景切换持续存活。
	if get_tree().current_scene == self:
		get_tree().current_scene = null
	call_deferred("_run")


func _run() -> void:
	if not _require(_autoload(&"GameManager") != null, "缺少 GameManager Autoload") \
			or not _require(_autoload(&"TurnManager") != null, "缺少 TurnManager Autoload") \
			or not _require(_autoload(&"InteractionCoordinator") != null, "缺少 InteractionCoordinator Autoload"):
		_finish()
		return
	if get_tree().change_scene_to_file(MAIN_MENU_SCENE) != OK:
		_fail("无法加载主菜单场景")
		_finish()
		return
	if not await _wait_until(func() -> bool: return get_tree().current_scene is MainMenu):
		_fail("主菜单未在时限内进入场景树")
		_finish()
		return

	# 首局使用探险博主，让回归真正经过一次“地图选择→
	# 指南挂起→恢复选择→棋子动画”的生产链路。
	var first_player_id: int = await _start_session(2, 0, "首局玩家", true)
	if first_player_id <= 0:
		_finish()
		return
	if not await _return_to_frontend():
		_finish()
		return
	var second_player_id: int = await _start_session(1, 1, "次局玩家", false)
	if second_player_id <= 0:
		_finish()
		return
	_require(second_player_id != first_player_id, "第二局不得复用第一局玩家节点")

	var game_manager: Node = _autoload(&"GameManager")
	var turn_manager: Node = _autoload(&"TurnManager")
	var interaction: Node = _autoload(&"InteractionCoordinator")
	game_manager.call(&"reset_session", false)
	_require(not bool(turn_manager.get("GameOn")), "最终清理后 TurnManager 仍在运行")
	_require((interaction.call(&"get_active_snapshot") as Dictionary).is_empty(), "最终清理后仍有活动交互")
	_require(int((turn_manager.call(&"get_modal_snapshot") as Dictionary).get("depth", -1)) == 0, "最终清理后仍有模态租约")
	_finish()


func _start_session(
	profession_position: int,
	region_position: int,
	display_name: String,
	exercise_interaction_chain: bool
) -> int:
	var game_manager: Node = _autoload(&"GameManager")
	var turn_manager: Node = _autoload(&"TurnManager")
	var interaction: Node = _autoload(&"InteractionCoordinator")
	var menu := get_tree().current_scene as MainMenu
	if not _require(menu != null, "当前场景不是主菜单"):
		return -1
	menu.set_reduce_motion(true)

	var home := menu.find_child("HomePage", true, false) as FrontendScreen
	var start_button := _find_button(home, "开始游戏")
	if not _require(start_button != null, "首页缺少开始游戏按钮"):
		return -1
	if not await _click_control(start_button, "首页开始游戏"):
		return -1
	if not await _wait_until(func() -> bool: return is_instance_valid(menu) and menu.get_current_screen() == &"mode"):
		_fail("点击开始游戏后未进入模式页")
		return -1

	var mode_page := menu.find_child("ModePage", true, false) as FrontendScreen
	var local_card := _find_card(mode_page, "本地游戏")
	if not _require(local_card != null, "模式页缺少本地游戏入口"):
		return -1
	if not await _click_control(local_card, "本地游戏模式卡"):
		return -1
	if not _require(menu.get_current_screen() == &"local_count", "本地游戏没有进入人数配置页"):
		return -1
	if not _require(menu.set_local_player_counts(1, 0), "无法配置单人本地会话"):
		return -1

	var count_page := menu.find_child("LocalCountPage", true, false) as FrontendScreen
	var next_button := _find_button(count_page, "下一步")
	if not _require(next_button != null, "人数配置页缺少下一步按钮"):
		return -1
	if not await _click_control(next_button, "人数配置下一步"):
		return -1
	if not await _wait_until(func() -> bool: return is_instance_valid(menu) and menu.get_current_screen() == &"player_setup"):
		_fail("人数配置后未进入玩家配置页")
		return -1

	var setup_page := menu.find_child("PlayerSetupPage", true, false) as FrontendPlayerSetupPage
	if not _require(setup_page != null, "玩家配置页不存在"):
		return -1
	var profession_cards := _controls_in_group(setup_page, &"frontend_profession_card")
	profession_cards.sort_custom(func(left: Control, right: Control) -> bool:
		return int(left.get_meta(&"profession_type")) < int(right.get_meta(&"profession_type"))
	)
	var region_buttons := _controls_in_group(setup_page, &"frontend_birthplace_option")
	region_buttons.sort_custom(func(left: Control, right: Control) -> bool:
		return int(left.get_meta(&"region")) < int(right.get_meta(&"region"))
	)
	if not _require(profession_position < profession_cards.size(), "职业选项数量不足"):
		return -1
	if not _require(region_position < region_buttons.size(), "出生点选项数量不足"):
		return -1
	if not await _click_control(profession_cards[profession_position], "职业卡"):
		return -1
	if not await _click_control(region_buttons[region_position], "出生点"):
		return -1
	setup_page.name_input.text = display_name
	setup_page.name_input.text_changed.emit(display_name)
	await get_tree().process_frame
	if not await _click_control(setup_page.confirm_button, "玩家配置确认"):
		return -1
	if not await _wait_until(func() -> bool: return is_instance_valid(menu) and menu.get_current_screen() == &"roster"):
		_fail("确认玩家后未进入阵容总览")
		return -1

	var roster_page := menu.find_child("RosterPage", true, false) as FrontendScreen
	var roster_start := _find_button(roster_page, "开始游戏")
	if not _require(roster_start != null and not roster_start.disabled, "阵容总览无法开始游戏"):
		return -1
	if not await _click_control(roster_start, "阵容总览开始游戏"):
		return -1
	if not await _wait_until(func() -> bool:
		var active_scene: Node = get_tree().current_scene
		return active_scene != null and active_scene.get_script() != null \
			and String(active_scene.get_script().resource_path) == "res://main_map.gd" \
			and bool(turn_manager.get("GameOn"))
	):
		_fail("正式前端没有在时限内切换到可运行的 main_map")
		return -1

	var running_players: Array = turn_manager.get("players") as Array
	if not _require(running_players.size() == 1, "对局玩家数量与前端配置不一致"):
		return -1
	if not _require(int(turn_manager.get("now_turn")) >= 1, "首回合没有启动"):
		return -1
	if not _require(get_tree().get_first_node_in_group("HUD") != null, "main_map 没有完整 HUD"):
		return -1
	if not _require(get_tree().get_first_node_in_group("MAP") != null, "main_map 没有地图节点"):
		return -1
	var active_setup: SessionSetup = game_manager.call(&"get_active_session_setup") as SessionSetup
	if not _require(active_setup != null and active_setup.players.size() == 1, "强类型会话快照没有进入对局"):
		return -1
	if not _require(active_setup.players[0].display_name == display_name, "对局读取了错误的玩家配置"):
		return -1
	var startup_interaction: Dictionary = interaction.call(&"get_active_snapshot") as Dictionary
	var startup_modal_depth: int = int((turn_manager.call(&"get_modal_snapshot") as Dictionary).get("depth", -1))
	if exercise_interaction_chain:
		if not _require(not startup_interaction.is_empty() and startup_modal_depth > 0, "探险博主准备阶段未开启正式选格交互"):
			return -1
	else:
		if not _require(startup_interaction.is_empty(), "首回合开始时遗留了前端交互"):
			return -1
		if not _require(startup_modal_depth == 0, "首回合开始时遗留了前端模态"):
			return -1
	if not await _complete_real_pointer_turn(
		get_tree().get_first_node_in_group("HUD") as HUD,
		exercise_interaction_chain
	):
		return -1
	return (running_players[0] as Node).get_instance_id()


func _complete_real_pointer_turn(hud: HUD, exercise_interaction_chain: bool) -> bool:
	var turn_manager: Node = _autoload(&"TurnManager")
	if not _require(hud != null, "无法通过真实 HUD 完成回合"):
		return false
	if exercise_interaction_chain and not await _exercise_live_interaction_chain(hud):
		return false
	if not await _wait_until(
		func() -> bool:
			return int(turn_manager.get("now_phase")) == TurnManager.TurnPhase.MOVING \
				and not bool(turn_manager.call(&"is_movement_locked"))
	):
		_fail("首回合未进入可操作的移动阶段")
		return false
	if not await _click_control(hud.btn_end_turn, "移动阶段结束"):
		return false
	if not await _wait_until(
		func() -> bool:
			return int(turn_manager.get("now_phase")) == TurnManager.TurnPhase.ACTION
	):
		_fail("结束移动后未进入 ACTION")
		return false
	if not await _click_control(hud.btn_food, "食物背包"):
		return false
	if not _require(hud.backpack_panel.visible, "真实点击没有打开食物背包"):
		return false
	var backpack_close := hud.backpack_panel.get_node_or_null("BtnClose") as Control
	if not await _click_control(backpack_close, "关闭食物背包"):
		return false
	if not _require(not hud.backpack_panel.visible, "食物背包关闭后仍可见"):
		return false
	if not await _click_control(hud.btn_end_turn, "行动阶段结束"):
		return false
	if not await _wait_until(
		func() -> bool:
			return int(turn_manager.get("now_turn")) >= 2 \
				and int(turn_manager.get("now_phase")) == TurnManager.TurnPhase.BEGIN
	):
		_fail("真实 HUD 操作后没有完成回合交接")
		return false
	# 探险博主在新回合 BEGIN 会合法地再开一次选格；这不是
	# 上一回合遗留。用正式“不移动”按钮收口，再检查全部状态归零。
	var interaction: Node = _autoload(&"InteractionCoordinator")
	var map := get_tree().get_first_node_in_group("MAP") as MAP
	if not (interaction.call(&"get_active_snapshot") as Dictionary).is_empty():
		if not _require(map != null and map.is_section_choice_active(&"profession"), "新回合出现了未识别的活动交互"):
			return false
		if not await _click_control(hud.btn_action, "新回合放弃职业移动"):
			return false
		if not await _wait_until(func() -> bool:
			return (interaction.call(&"get_active_snapshot") as Dictionary).is_empty() \
				and not map.is_section_choice_active() \
				and int((turn_manager.call(&"get_modal_snapshot") as Dictionary).get("depth", -1)) == 0
		):
			_fail("新回合放弃职业移动后生命周期未归零")
			return false
	return _require(
		(interaction.call(&"get_active_snapshot") as Dictionary).is_empty()
			and int((turn_manager.call(&"get_modal_snapshot") as Dictionary).get("depth", -1)) == 0
			and not get_tree().paused,
		"真实回合结束后交互或模态未归零"
	)


func _exercise_live_interaction_chain(hud: HUD) -> bool:
	var turn_manager: Node = _autoload(&"TurnManager")
	var interaction: Node = _autoload(&"InteractionCoordinator")
	var map := get_tree().get_first_node_in_group("MAP") as MAP
	var running_players: Array = turn_manager.get("players") as Array
	if not _require(map != null and running_players.size() == 1, "全链路选择缺少地图或玩家"):
		return false
	var player := running_players[0] as PlayerClass
	if not _require(
		ProfessionManager.is_skill_enabled(player, ProfessionManager.ADVENTURE_BLOGGER),
		"全链路回归未使用探险博主"
	):
		return false
	var old_position := player.now_pos
	if not await _wait_until(func() -> bool:
		return not (interaction.call(&"get_active_snapshot") as Dictionary).is_empty() \
			and map.is_section_choice_active(&"profession")
	):
		_fail("探险博主没有开启正式地图选择交互")
		return false
	var request := ProfessionManager.get_pending_section_choice_request()
	if not _require(request != null and not request.options.is_empty(), "探险博主地图选择没有合法终点"):
		return false
	var target := request.options[0] as MapSection
	var before_guide: Dictionary = interaction.call(&"get_active_snapshot") as Dictionary
	var before_time: float = float(before_guide.get("time_left", 0.0))
	if not await _click_control(hud.guide_button as Control, "选择期间打开指南"):
		return false
	if not await _wait_until(func() -> bool:
		return hud.game_guide != null and hud.game_guide.is_guide_open()
	):
		_fail("地图选择期间指南未打开")
		return false
	var suspended: Dictionary = interaction.call(&"get_active_snapshot") as Dictionary
	if not _require(
		bool(suspended.get("suspended", false)) and get_tree().paused,
		"指南没有同时挂起选择倒计时与场景树"
	):
		return false
	for _frame: int in range(12):
		await get_tree().process_frame
	var frozen: Dictionary = interaction.call(&"get_active_snapshot") as Dictionary
	if not _require(
		absf(float(frozen.get("time_left", 0.0)) - before_time) < 0.2,
		"指南打开期间选择倒计时仍在流逝"
	):
		return false
	var guide_close := hud.game_guide.find_child("CloseButton", true, false) as Control
	if not await _click_control(guide_close, "关闭指南并恢复选择"):
		return false
	if not await _wait_until(func() -> bool:
		return not hud.game_guide.is_guide_open() and not get_tree().paused
	):
		_fail("关闭指南后没有释放场景树暂停")
		return false
	var resumed: Dictionary = interaction.call(&"get_active_snapshot") as Dictionary
	if not _require(
		not resumed.is_empty() and not bool(resumed.get("suspended", true)),
		"关闭指南后地图选择未恢复"
	):
		return false

	# 从 MapSection 的生产信号入口提交，继续经过 MAP、HUD、
	# ProfessionManager 和 InteractionCoordinator，而不直接填写结果。
	target.section_clicked.emit(target)
	if not await _wait_until(func() -> bool:
		return player.now_pos == target.location_index \
			and old_position != player.now_pos \
			and (interaction.call(&"get_active_snapshot") as Dictionary).is_empty() \
			and not map.is_section_choice_active() \
			and int((turn_manager.call(&"get_modal_snapshot") as Dictionary).get("depth", -1)) == 0
	):
		_fail("地图选择提交后未完成棋子移动或生命周期未归零")
		return false
	return _require(
		bool(turn_manager.get("GameOn")) \
			and not get_tree().paused \
			and not (turn_manager.get("turn_timer") as Timer).is_stopped(),
		"全链路选择结束后未恢复回合推进"
	)


func _return_to_frontend() -> bool:
	var game_manager: Node = _autoload(&"GameManager")
	var turn_manager: Node = _autoload(&"TurnManager")
	var interaction: Node = _autoload(&"InteractionCoordinator")
	if int(game_manager.call(&"return_to_main_menu")) != OK:
		_fail("无法从对局返回主菜单")
		return false
	if not await _wait_until(func() -> bool: return get_tree().current_scene is MainMenu):
		_fail("返回主菜单超时")
		return false
	if not _require(not get_tree().paused, "返回主菜单后 SceneTree 仍处于暂停状态"):
		return false
	if not _require(not bool(turn_manager.get("GameOn")) and (turn_manager.get("players") as Array).is_empty(), "返回主菜单后旧对局仍在运行"):
		return false
	if not _require((interaction.call(&"get_active_snapshot") as Dictionary).is_empty(), "返回主菜单后仍有活动交互"):
		return false
	if not _require(int((turn_manager.call(&"get_modal_snapshot") as Dictionary).get("depth", -1)) == 0, "返回主菜单后仍有模态租约"):
		return false
	return true


func _find_button(root: Node, text_value: String) -> Button:
	if root == null:
		return null
	for node: Node in _descendants(root):
		if node is Button and (node as Button).text == text_value:
			return node as Button
	return null


func _find_card(root: Node, title: String) -> FrontendStatefulCard:
	if root == null:
		return null
	for node: Node in _descendants(root):
		if node is FrontendStatefulCard and (node as FrontendStatefulCard).title == title:
			return node as FrontendStatefulCard
	return null


func _controls_in_group(root: Node, group_name: StringName) -> Array[Control]:
	var result: Array[Control] = []
	for node: Node in _descendants(root):
		if node is Control and node.is_in_group(group_name):
			result.append(node as Control)
	return result


func _descendants(root: Node) -> Array[Node]:
	var result: Array[Node] = []
	var pending: Array[Node] = []
	for child: Node in root.get_children():
		pending.append(child)
	while not pending.is_empty():
		var current: Node = pending.pop_front()
		result.append(current)
		for child: Node in current.get_children():
			pending.append(child)
	return result


func _autoload(node_name: StringName) -> Node:
	if get_tree() == null or get_tree().root == null:
		return null
	return get_tree().root.get_node_or_null(NodePath(String(node_name)))


func _click_control(control: Control, label: String) -> bool:
	if not _require(control != null and is_instance_valid(control), "%s控件不存在" % label):
		return false
	var hovered: Control = await _pointer.click(control)
	return _require(hovered == control, "%s未被单次真实鼠标点击命中" % label)


func _wait_until(predicate: Callable, timeout_seconds: float = WAIT_TIMEOUT_SECONDS) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() <= deadline:
		if predicate.call():
			return true
		await get_tree().process_frame
	return bool(predicate.call())


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	_fail(message)
	return false


func _fail(message: String) -> void:
	_failed = true
	push_error("FRONTEND_SESSION_E2E: %s" % message)


func _finish() -> void:
	if _failed:
		get_tree().quit(1)
	else:
		print("FRONTEND_SESSION_E2E: PASS")
		get_tree().quit(0)
