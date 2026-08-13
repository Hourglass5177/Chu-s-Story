extends GutTest

class MovementProbeMap extends MAP:
	var reachable_refresh_count: int = 0

	func _ready() -> void:
		pass

	func _show_reachable_areas() -> void:
		reachable_refresh_count += 1

class MovementProbeHUD extends HUD:
	func _ready() -> void:
		pass

	func _update_player_stats(_player: PlayerClass) -> void:
		pass

	func update_camera_view(_duration: float = 0.4) -> void:
		pass

	func _update_button_states(_phase: TurnManager.TurnPhase) -> void:
		pass

class MovementProbePlayer extends PlayerClass:
	func _ready() -> void:
		pass

var _players_backup: Array[PlayerClass]
var _game_on_backup: bool
var _phase_backup: TurnManager.TurnPhase
var _player_index_backup: int
var _hud_backup: HUD
var _regional_backup: Dictionary
var _market_backup: Array[非遗牌]

func before_each() -> void:
	_players_backup.assign(TurnManager.players)
	_game_on_backup = TurnManager.GameOn
	_phase_backup = TurnManager.now_phase
	_player_index_backup = TurnManager.now_player_index
	_hud_backup = ResourceManager.hud
	_regional_backup = ResourceManager.地区非遗牌库.duplicate(true)
	_market_backup = MarketManager.get_inventory()
	ResourceManager.hud = null
	MarketManager.reset_for_new_game()
	TurnManager.turn_timer.stop()
	TurnManager.movement_lock_active = false

func after_each() -> void:
	TurnManager.turn_timer.stop()
	TurnManager.movement_lock_active = false
	TurnManager.players.assign(_players_backup)
	TurnManager.player_num = TurnManager.players.size()
	TurnManager.GameOn = _game_on_backup
	TurnManager.now_phase = _phase_backup
	TurnManager.now_player_index = _player_index_backup
	ResourceManager.hud = _hud_backup
	ResourceManager.地区非遗牌库 = _regional_backup.duplicate(true)
	MarketManager.reset_for_new_game()
	for card: 非遗牌 in _market_backup:
		MarketManager.deposit_card(card, &"test_restore")

func test_path_prefers_energy_then_steps_and_honors_both_limits() -> void:
	var map := MAP.new()
	var start := Vector3i.ZERO
	var expensive := Vector3i(1, -1, 0)
	var detour_a := Vector3i(0, -1, 1)
	var detour_b := Vector3i(1, -2, 1)
	var target := Vector3i(2, -2, 0)
	_add_section(map, start, 0)
	_add_section(map, expensive, 3)
	_add_section(map, detour_a, 1)
	_add_section(map, detour_b, 1)
	_add_section(map, target, 1)
	var result := map._best_path(start, target, 3, 10)
	assert_eq(result["cost"], 3, "应优先选择精力消耗更低的三步路线")
	assert_eq(result["steps"], 3)
	map.grid_map[expensive].cost = 2
	result = map._best_path(start, target, 3, 10)
	assert_eq(result["cost"], 3)
	assert_eq(result["steps"], 2, "耗能相同时应选择步数更少的路线")
	assert_true(map._best_path(start, target, 2, 2).is_empty(), "步数与精力必须同时满足")
	for section: MapSection in map.grid_map.values():
		section.free()
	map.free()

func test_reachable_areas_refresh_from_new_position_with_remaining_steps() -> void:
	var map := MAP.new()
	var origin := Vector3i.ZERO
	var first_stop := Vector3i(1, -1, 0)
	var second_stop := Vector3i(2, -2, 0)
	var final_stop := Vector3i(3, -3, 0)
	_add_section(map, origin, 1)
	_add_section(map, first_stop, 1)
	_add_section(map, second_stop, 1)
	_add_section(map, final_stop, 1)

	var player := PlayerClass.new()
	player.now_pos = first_stop
	player.maxMove = 2
	player.current_energy = 3
	map.grid_map[origin].is_reached = true
	map.grid_map[first_stop].is_reached = true
	map.grid_map[first_stop].is_occupied = true
	TurnManager.players.assign([player])
	TurnManager.player_num = 1
	TurnManager.now_player_index = 0
	TurnManager.now_phase = TurnManager.TurnPhase.MOVING
	TurnManager.GameOn = true

	map._show_reachable_areas()

	assert_false(map.grid_map[origin].is_reachable, "本阶段已经走过的格子不能回走")
	assert_true(map.grid_map[second_stop].is_reachable, "第一次移动后应按剩余步数重新开放相邻格")
	assert_true(map.grid_map[final_stop].is_reachable, "剩余两步内的后续格应继续可选")

	for section: MapSection in map.grid_map.values():
		section.free()
	player.free()
	map.free()

func test_completed_partial_move_requests_a_new_reachable_area_refresh() -> void:
	var map := MovementProbeMap.new()
	var origin := Vector3i.ZERO
	var destination := Vector3i(1, -1, 0)
	_add_section(map, origin, 1)
	_add_section(map, destination, 1)
	map.grid_map[origin].is_occupied = true

	var hud := MovementProbeHUD.new()
	hud.btn_end_turn = Button.new()
	hud.add_child(hud.btn_end_turn)
	var player := MovementProbePlayer.new()
	player.map = map
	player.hud = hud
	player.now_pos = origin
	player.maxMove = 2
	player.current_energy = 3
	var score_badge := Node2D.new()
	score_badge.name = "ScoreBadge"
	var score_label := Label.new()
	score_label.name = "Score"
	score_badge.add_child(score_label)
	player.add_child(score_badge)
	add_child(player)
	TurnManager.players.assign([player])
	TurnManager.player_num = 1
	TurnManager.now_player_index = 0
	TurnManager.now_phase = TurnManager.TurnPhase.MOVING
	TurnManager.GameOn = true

	var moved := await player.move_along_path([Vector2(20.0, 0.0)], 1, destination)

	assert_true(moved)
	assert_eq(player.maxMove, 1)
	assert_eq(map.reachable_refresh_count, 1, "一段移动完成后必须重新计算剩余可达格")

	player.free()
	hud.free()
	for section: MapSection in map.grid_map.values():
		section.free()
	map.free()

func test_movement_lock_pauses_timer_and_blocks_phase_progression() -> void:
	TurnManager.GameOn = true
	TurnManager.now_phase = TurnManager.TurnPhase.MOVING
	TurnManager.turn_timer.start(10.0)
	assert_true(TurnManager.begin_movement_lock())
	assert_true(TurnManager.turn_timer.is_stopped())
	TurnManager._emit_next_phase(TurnManager.TurnPhase.ACTION)
	TurnManager._on_timer_timeout()
	assert_eq(TurnManager.now_phase, TurnManager.TurnPhase.MOVING)
	TurnManager.end_movement_lock()
	assert_false(TurnManager.turn_timer.is_stopped())
	assert_between(TurnManager.turn_timer.time_left, 9.0, 10.0)

func test_two_player_game_requires_two_eliminations_or_score_limit() -> void:
	var first := PlayerClass.new()
	var second := PlayerClass.new()
	TurnManager.players.assign([first, second])
	TurnManager.player_num = 2
	first.alive = false
	assert_false(TurnManager.has_reached_elimination_limit())
	second.alive = false
	assert_true(TurnManager.has_reached_elimination_limit())
	second.alive = true
	first.current_score = 20
	assert_true(TurnManager.has_player_reached_score_limit())
	first.free()
	second.free()

func test_collecting_feiyi_keeps_action_phase() -> void:
	var player := PlayerClass.new()
	player.current_energy = 6
	var section := MapSection.new()
	section.region = MapSection.REGION.鄂州
	var card := _make_feiyi("行动阶段收集", 非遗牌.CardCategory.戏曲表演)
	ResourceManager.地区非遗牌库 = {MapSection.REGION.鄂州: [card]}
	TurnManager.now_phase = TurnManager.TurnPhase.ACTION
	TurnManager.GameOn = true
	assert_eq(ResourceManager.get_feiyi(player, section), card)
	assert_eq(TurnManager.now_phase, TurnManager.TurnPhase.ACTION)
	assert_eq(player.current_energy, 5)
	player.free()
	section.free()

func test_zero_energy_during_moving_can_recover_with_food_before_turn_end() -> void:
	var player := PlayerClass.new()
	var food := 食物牌.new()
	food.card_name = "回合末判定测试"
	player.current_energy = 1
	player.食物牌手牌.append(food)
	TurnManager.players.assign([player])
	TurnManager.player_num = 1
	TurnManager.now_player_index = 0
	TurnManager.GameOn = true
	TurnManager.now_phase = TurnManager.TurnPhase.MOVING

	ResourceManager.modify_energy(player, -1, "移动消耗测试")
	assert_eq(player.current_energy, 0)
	assert_true(player.alive, "移动阶段精力归零不得提前淘汰")

	TurnManager.now_phase = TurnManager.TurnPhase.ACTION
	assert_true(ResourceManager.consume_food(player, food), "精力为零时仍应能在 ACTION 吃食物")
	assert_eq(player.current_energy, 2)
	assert_false(await player.resolve_turn_end_elimination())
	assert_true(player.alive, "回合末精力已恢复时必须存活")
	player.free()

func test_handicraft_effect_cannot_stack_in_one_moving_phase() -> void:
	var player := PlayerClass.new()
	player.onTurn = true
	player.maxMove = 4
	var first := _make_feiyi("第一张技艺", 非遗牌.CardCategory.手工技艺)
	var second := _make_feiyi("第二张技艺", 非遗牌.CardCategory.手工技艺)
	player.非遗牌手牌.assign([first, second])
	TurnManager.players.assign([player])
	TurnManager.player_num = 1
	TurnManager.now_player_index = 0
	TurnManager.now_phase = TurnManager.TurnPhase.MOVING
	TurnManager.GameOn = true
	assert_true(ResourceManager.use_feiyi(player, first))
	assert_eq(player.maxMove, 8)
	assert_false(ResourceManager.use_feiyi(player, second))
	assert_eq(player.maxMove, 8)
	assert_true(player.非遗牌手牌.has(second), "第二张牌不应被消耗")
	player.free()

func test_resource_totals_come_from_actual_loaded_cards() -> void:
	var regional_total := 0
	for count: int in ResourceManager.地区非遗牌上限字典.values():
		regional_total += count
	var category_total := 0
	for count: int in ResourceManager.类别非遗牌上限字典.values():
		category_total += count
	assert_gt(regional_total, 0)
	assert_eq(category_total, regional_total)

func _add_section(map: MAP, coordinate: Vector3i, cost: int) -> void:
	var section := MapSection.new()
	section.location_index = coordinate
	section.cost = cost
	map.grid_map[coordinate] = section

func _make_feiyi(display_name: String, category: 非遗牌.CardCategory) -> 非遗牌:
	var card := 非遗牌.new()
	card.card_name = display_name
	card.category = category
	return card
