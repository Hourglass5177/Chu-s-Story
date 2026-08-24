extends GutTest


class PassiveProbeMap extends MAP:
	func _ready() -> void:
		pass

	func _show_reachable_areas() -> void:
		pass


class PassiveProbeHUD extends HUD:
	var messages: Array[String] = []

	func _ready() -> void:
		pass

	func _update_player_stats(_player: PlayerClass) -> void:
		pass

	func update_camera_view(_duration: float = 0.4) -> void:
		pass

	func _update_button_states(_phase: TurnManager.TurnPhase) -> void:
		pass

	func _update_game_informs(message: String) -> void:
		messages.append(message)


class PassiveProbePlayer extends PlayerClass:
	func _ready() -> void:
		pass


var _players_backup: Array[PlayerClass] = []
var _game_on_backup: bool = false
var _phase_backup: TurnManager.TurnPhase = TurnManager.TurnPhase.BEGIN
var _player_index_backup: int = 0
var _resource_hud_backup: HUD = null
var _food_deck_backup: Array[卡牌基类] = []
var _market_inventory_backup: Array[非遗牌] = []


func before_each() -> void:
	_players_backup.assign(TurnManager.players)
	_game_on_backup = TurnManager.GameOn
	_phase_backup = TurnManager.now_phase
	_player_index_backup = TurnManager.now_player_index
	_resource_hud_backup = ResourceManager.hud
	_food_deck_backup.assign(ResourceManager.食物牌库)
	_market_inventory_backup.assign(MarketManager.get_inventory())
	TurnManager.turn_timer.stop()
	TurnManager.movement_lock_active = false
	TurnManager.GameOn = true
	TurnManager.now_phase = TurnManager.TurnPhase.ACTION
	TurnManager.now_player_index = 0
	ResourceManager.hud = null
	ResourceManager.食物牌库.clear()
	MarketManager.reset_for_new_game()
	ProfessionManager.reset_for_new_game()


func after_each() -> void:
	TurnManager.turn_timer.stop()
	TurnManager.movement_lock_active = false
	TurnManager.players.assign(_players_backup)
	TurnManager.player_num = TurnManager.players.size()
	TurnManager.GameOn = _game_on_backup
	TurnManager.now_phase = _phase_backup
	TurnManager.now_player_index = _player_index_backup
	ResourceManager.hud = _resource_hud_backup
	ResourceManager.食物牌库.assign(_food_deck_backup)
	MarketManager.reset_for_new_game()
	for card: 非遗牌 in _market_inventory_backup:
		MarketManager.deposit_card(card, &"test_restore")
	ProfessionManager.reset_for_new_game()


func test_food_blogger_can_consume_three_foods_but_not_four() -> void:
	var player := _make_player(PlayerClass.PlayerCharacter.美食博主)
	var foods: Array[食物牌] = []
	for index: int in 4:
		var food := _make_food("食物%d" % index)
		foods.append(food)
		player.食物牌手牌.append(food)
	TurnManager.players.assign([player])
	TurnManager.player_num = 1

	assert_true(ResourceManager.consume_food(player, foods[0]))
	assert_true(ResourceManager.consume_food(player, foods[1]))
	assert_true(ResourceManager.consume_food(player, foods[2]))
	assert_eq(player.food_used_count_this_turn, 3)
	assert_true(player.food_used_this_turn, "旧布尔视图应继续反映本回合已经吃过食物")
	assert_false(ResourceManager.consume_food(player, foods[3]))
	assert_true(player.食物牌手牌.has(foods[3]))

	player.free()


func test_food_limit_follows_current_profession_dynamically() -> void:
	var player := _make_player(PlayerClass.PlayerCharacter.美食博主)
	var foods: Array[食物牌] = [_make_food("甲"), _make_food("乙"), _make_food("丙")]
	player.食物牌手牌.assign(foods)
	TurnManager.players.assign([player])
	TurnManager.player_num = 1

	assert_true(ResourceManager.consume_food(player, foods[0]))
	player.player_types = PlayerClass.PlayerCharacter.生活博主
	assert_false(ResourceManager.consume_food(player, foods[1]), "失去美食职业后应立即恢复普通上限")
	player.player_types = PlayerClass.PlayerCharacter.美食博主
	assert_true(ResourceManager.consume_food(player, foods[1]), "重新获得美食职业后应按已有次数继续计算")
	assert_true(ProfessionManager.block_skill(player, 1))
	assert_false(ResourceManager.consume_food(player, foods[2]), "技能封锁后应立即恢复普通每回合1张上限")

	player.free()


func test_commercial_blogger_market_price_and_authoritative_charge_are_half() -> void:
	var card := 非遗牌.new()
	card.card_name = "折扣测试牌"
	card.base_score = 2
	var regular := _make_player(PlayerClass.PlayerCharacter.美食博主)
	var commercial := _make_player(PlayerClass.PlayerCharacter.商业博主)
	commercial.current_money = 350

	assert_eq(MarketManager.get_buy_price(card), 700, "未提供玩家时保持普通价格兼容")
	assert_eq(MarketManager.get_buy_price(card, regular), 700)
	assert_eq(MarketManager.get_buy_price(card, commercial), 350)
	assert_true(ProfessionManager.block_skill(commercial, 1))
	assert_eq(MarketManager.get_buy_price(card, commercial), 700, "技能封锁时显示价格应恢复原价")
	assert_true(ProfessionManager.clear_skill_block(commercial))
	assert_true(MarketManager.deposit_card(card, &"test"))
	assert_true(MarketManager.buy_card(commercial, card, 1))
	assert_eq(commercial.current_money, 0)
	assert_true(commercial.非遗牌手牌.has(card))

	regular.free()
	commercial.free()


func test_life_blogger_normal_work_costs_no_energy() -> void:
	var life := _make_player(PlayerClass.PlayerCharacter.生活博主)
	var regular := _make_player(PlayerClass.PlayerCharacter.美食博主)
	life.current_energy = 0
	regular.current_energy = 3

	assert_true(ResourceManager.process_work_salary(life, 1))
	assert_eq(life.current_energy, 0)
	assert_eq(life.current_money, 1250)
	assert_true(ResourceManager.process_work_salary(regular, 1))
	assert_eq(regular.current_energy, 2)
	assert_eq(regular.current_money, 1250)
	life.current_energy = 1
	assert_true(ProfessionManager.block_skill(life, 1))
	assert_true(ResourceManager.process_work_salary(life, 1))
	assert_eq(life.current_energy, 0, "技能封锁时普通打工仍应消耗1点精力")

	life.free()
	regular.free()


func test_completed_work_reports_the_actual_final_salary() -> void:
	var map := PassiveProbeMap.new()
	var work_coord := Vector3i.ZERO
	var work_section := _make_section(work_coord, MapSection.SectionType.打工, Vector2.ZERO)
	map.grid_map[work_coord] = work_section
	var hud := PassiveProbeHUD.new()
	hud.btn_action = Button.new()
	hud.btn_food = Button.new()
	hud.add_child(hud.btn_action)
	hud.add_child(hud.btn_food)
	var player := PassiveProbePlayer.new()
	player.player_name = "打工测试"
	player.player_types = PlayerClass.PlayerCharacter.美食博主
	player.map = map
	player.hud = hud
	player.onTurn = true
	player.now_pos = work_coord
	player.current_energy = 3
	player.current_money = 500
	player.is_working = true
	player.work_turns = 2
	player.work_turns_left = 1

	await player.execute_tile_action()

	assert_false(player.is_working)
	assert_eq(player.current_money, 850)
	assert_eq(hud.messages.back(), "打工结束，获得350积分点！")

	player.free()
	hud.free()
	work_section.free()
	map.free()


func test_returned_shop_foods_keep_display_order_and_do_not_duplicate() -> void:
	var first := _make_food("第一张")
	var second := _make_food("第二张")
	var third := _make_food("第三张")
	var cards: Array[食物牌] = [first, second, third]

	ResourceManager.return_shop_foods_to_bottom(cards)
	ResourceManager.return_shop_foods_to_bottom(cards)
	assert_eq(ResourceManager.食物牌库.size(), 3)
	var redrawn: Array[食物牌] = ResourceManager.draw_shop_foods(3)
	assert_eq(redrawn, cards, "实际商店抽牌也必须保持原展示顺序")


func test_travel_blogger_resolves_scenery_reward_only_on_action_entry() -> void:
	var map := PassiveProbeMap.new()
	var origin := Vector3i.ZERO
	var scenery_coord := Vector3i(1, -1, 0)
	var origin_section := _make_section(origin, MapSection.SectionType.一般, Vector2.ZERO)
	var scenery := _make_section(scenery_coord, MapSection.SectionType.风景, Vector2(20.0, 0.0))
	map.grid_map[origin] = origin_section
	map.grid_map[scenery_coord] = scenery
	origin_section.is_occupied = true

	var hud := PassiveProbeHUD.new()
	hud.btn_end_turn = Button.new()
	hud.add_child(hud.btn_end_turn)
	var player := PassiveProbePlayer.new()
	player.player_name = "旅行测试"
	player.player_types = PlayerClass.PlayerCharacter.旅行博主
	player.map = map
	player.hud = hud
	player.onTurn = true
	player.now_pos = origin
	player.maxMove = 3
	player.current_energy = 6
	var score_badge := Node2D.new()
	score_badge.name = "ScoreBadge"
	var score_label := Label.new()
	score_label.name = "Score"
	score_badge.add_child(score_label)
	player.add_child(score_badge)
	add_child(player)
	TurnManager.players.assign([player])
	TurnManager.player_num = 1
	TurnManager.now_phase = TurnManager.TurnPhase.MOVING
	ResourceManager.hud = hud
	AchievementManager.reset_for_new_game([player])

	assert_true(await player.move_along_path([scenery.global_position], 0, scenery_coord))
	assert_eq(player.current_money, 500, "移动阶段抵达风景格时不得提前结算旅行奖励")
	assert_eq(player.current_energy, 6, "移动阶段不得提前结算首次打卡精力")
	assert_true(await player.move_along_path([origin_section.global_position], 0, origin))
	assert_eq(player.current_money, 500, "同次移动中途经过风景格不得获得奖励")
	assert_true(await player.move_along_path([scenery.global_position], 0, scenery_coord))
	assert_eq(player.current_money, 500)
	TurnManager.now_phase = TurnManager.TurnPhase.ACTION
	player._on_phase_changed(TurnManager.TurnPhase.ACTION)
	assert_eq(player.current_money, 750)
	assert_eq(player.current_energy, 9)
	assert_eq(hud.messages.back(), "旅行测试 欣赏风景，回复3点精力，获得250积分点！", "首次打卡的精力与职业积分应合并提示")
	player.auto_trigger_scenery(scenery)
	assert_eq(player.current_money, 750, "同一到达编号在 ACTION 中不得重复结算")

	TurnManager.now_phase = TurnManager.TurnPhase.MOVING
	player.maxMove = 2
	assert_true(await player.move_along_path([origin_section.global_position], 0, origin))
	assert_true(await player.move_along_path([scenery.global_position], 0, scenery_coord))
	assert_eq(player.current_money, 750, "重复到达也必须等进入 ACTION 才结算")
	TurnManager.now_phase = TurnManager.TurnPhase.ACTION
	player._on_phase_changed(TurnManager.TurnPhase.ACTION)
	assert_eq(player.current_money, 1000, "重复到达同一风景也应再次获得职业奖励")
	assert_eq(player.current_energy, 9, "重复打卡不得再次获得首次打卡精力")
	assert_eq(hud.messages.back(), "旅行测试 到达风景区，获得250积分点！", "重复到达的职业积分应单独提示")

	assert_true(ProfessionManager.block_skill(player, 1))
	TurnManager.now_phase = TurnManager.TurnPhase.MOVING
	player.maxMove = 2
	assert_true(await player.move_along_path([origin_section.global_position], 0, origin))
	assert_true(await player.move_along_path([scenery.global_position], 0, scenery_coord))
	TurnManager.now_phase = TurnManager.TurnPhase.ACTION
	player._on_phase_changed(TurnManager.TurnPhase.ACTION)
	assert_eq(player.current_money, 1000, "技能封锁时普通到达风景不应获得职业奖励")

	AchievementManager.reset_for_new_game([])
	player.free()
	hud.free()
	origin_section.free()
	scenery.free()
	map.free()


func _make_player(profession: PlayerClass.PlayerCharacter) -> PlayerClass:
	var player := PlayerClass.new()
	player.player_types = profession
	player.current_energy = 0
	player.current_money = 1000
	return player


func _make_food(display_name: String) -> 食物牌:
	var food := 食物牌.new()
	food.card_name = display_name
	food.food_type = 食物牌.FoodType.市级
	return food


func _make_section(coordinate: Vector3i, section_type: MapSection.SectionType, world_position: Vector2) -> MapSection:
	var section := MapSection.new()
	section.location_index = coordinate
	section.type = section_type
	section.position = world_position
	return section
