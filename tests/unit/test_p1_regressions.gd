extends GutTest

var _food_deck_backup: Array[卡牌基类]
var _players_backup: Array[PlayerClass]
var _game_on_backup: bool
var _phase_backup: TurnManager.TurnPhase
var _player_index_backup: int
var _hud_backup: HUD
var _market_backup: Array[非遗牌]

func before_each() -> void:
	_food_deck_backup.assign(ResourceManager.食物牌库)
	_players_backup.assign(TurnManager.players)
	_game_on_backup = TurnManager.GameOn
	_phase_backup = TurnManager.now_phase
	_player_index_backup = TurnManager.now_player_index
	_hud_backup = ResourceManager.hud
	_market_backup = MarketManager.get_inventory()
	MarketManager.reset_for_new_game()
	ResourceManager.hud = null

func after_each() -> void:
	ResourceManager.食物牌库.assign(_food_deck_backup)
	TurnManager.players.assign(_players_backup)
	TurnManager.player_num = TurnManager.players.size()
	TurnManager.GameOn = _game_on_backup
	TurnManager.now_phase = _phase_backup
	TurnManager.now_player_index = _player_index_backup
	ResourceManager.hud = _hud_backup
	MarketManager.reset_for_new_game()
	for card: 非遗牌 in _market_backup:
		MarketManager.deposit_card(card, &"test_restore")

func test_two_dice_rolls_stay_in_2_to_12_and_center_near_7() -> void:
	var player := PlayerClass.new()
	seed(20260805)
	var total := 0
	var minimum := 12
	var maximum := 2
	for _index in 30:
		var result := player.do_roll_dice()
		assert_between(result, 2, 12)
		total += result
		minimum = mini(minimum, result)
		maximum = maxi(maximum, result)
	var average := float(total) / 30.0
	assert_lte(minimum, 4, "固定种子样本应覆盖双骰低位")
	assert_gte(maximum, 10, "固定种子样本应覆盖双骰高位")
	assert_between(average, 5.5, 8.5, "2D6 样本中心应接近 7")
	player.free()

func test_consumed_food_returns_once_and_cannot_duplicate() -> void:
	var player := PlayerClass.new()
	var food := 食物牌.new()
	var second_food := 食物牌.new()
	food.card_name = "回库测试食物"
	second_food.card_name = "本回合第二张食物"
	player.食物牌手牌.assign([food, second_food])
	player.current_energy = 4
	player.current_money = 1000
	ResourceManager.食物牌库.clear()
	TurnManager.players.assign([player])
	TurnManager.player_num = 1
	TurnManager.now_player_index = 0
	TurnManager.now_phase = TurnManager.TurnPhase.ACTION
	TurnManager.GameOn = true
	assert_true(ResourceManager.consume_food(player, food))
	assert_eq(player.current_energy, 6)
	assert_eq(player.current_money, 1000, "市级食物不再提供积分选项")
	assert_false(player.食物牌手牌.has(food))
	assert_eq(ResourceManager.食物牌库.count(food), 1)
	assert_false(ResourceManager.consume_food(player, food))
	assert_eq(ResourceManager.食物牌库.count(food), 1)
	assert_false(ResourceManager.consume_food(player, second_food), "同一回合不得享用第二张食物")
	assert_true(player.食物牌手牌.has(second_food))
	player.reset_turn_usage_limits()
	assert_true(ResourceManager.consume_food(player, second_food), "新回合应重置食物使用限制")
	player.free()

func test_score_breakdown_matches_total_and_marks_regional_combo() -> void:
	var player := PlayerClass.new()
	var region := MapSection.REGION.鄂州
	var region_limits_backup := ResourceManager.地区非遗牌上限字典.duplicate(true)
	ResourceManager.地区非遗牌上限字典[region] = 99
	for index in 5:
		var card := 非遗牌.new()
		card.card_name = "地域组合%d" % index
		card.region = 非遗牌.REGION.鄂州
		card.category = 非遗牌.CardCategory.戏曲表演
		player.非遗牌手牌.append(card)
	var breakdown := ResourceManager.get_score_breakdown(player)
	assert_eq(int(breakdown["regional_combo_score"]), 5)
	assert_eq(int(breakdown["total_score"]), int(breakdown["base_score"]) + int(breakdown["category_combo_score"]) + int(breakdown["category_completion_score"]) + 5)
	assert_true(breakdown["region_annotations"].has(region))
	assert_has(breakdown["region_annotations"][region], "触发同城5张得分+5")
	ResourceManager.calculate_victory_score(player)
	assert_eq(player.current_score, int(breakdown["total_score"]))
	ResourceManager.地区非遗牌上限字典 = region_limits_backup
	player.free()

func test_all_city_foods_use_two_energy_digital_card_faces() -> void:
	var file_names := Array(DirAccess.get_files_at("res://Cards/食物牌"))
	var checked := 0
	for file_name: String in file_names:
		if not file_name.ends_with(".tres"):
			continue
		var food := load("res://Cards/食物牌/%s" % file_name) as 食物牌
		assert_not_null(food, file_name)
		if food == null or food.food_type != 食物牌.FoodType.市级:
			continue
		checked += 1
		assert_eq(food.effect_description, "精力 +2", food.card_name)
		assert_string_contains(food.image_of_front.resource_path, "/数字版/", food.card_name)
		assert_eq(food.image_of_front.resource_path.get_file().get_basename(), food.card_name, "牌名应与牌面文件对应")
	assert_eq(checked, 20)

func test_used_feiyi_is_removed_and_applies_effect() -> void:
	var player := PlayerClass.new()
	var card := 非遗牌.new()
	card.card_name = "戏曲效果测试"
	card.category = 非遗牌.CardCategory.戏曲表演
	player.current_energy = 3
	player.onTurn = true
	player.非遗牌手牌.append(card)
	TurnManager.players.assign([player])
	TurnManager.player_num = 1
	TurnManager.now_player_index = 0
	TurnManager.now_phase = TurnManager.TurnPhase.ACTION
	TurnManager.GameOn = true
	assert_true(ResourceManager.use_feiyi(player, card))
	assert_eq(player.current_energy, 6)
	assert_false(player.非遗牌手牌.has(card))
	assert_true(MarketManager.get_inventory().has(card), "已使用的非国家级非遗牌应自动进入全局研究所")
	player.free()

func test_score_combo_uses_highest_category_tier_only() -> void:
	var player := PlayerClass.new()
	var test_regions := [0, 1, 2, 3, 5]
	for index in 5:
		var card := 非遗牌.new()
		card.card_name = "组合计分%d" % index
		card.category = 非遗牌.CardCategory.手工技艺
		card.region = test_regions[index]
		player.非遗牌手牌.append(card)
	ResourceManager.calculate_victory_score(player)
	assert_eq(player.current_score, 8, "5 张手工技艺应为基础 5 分加单个最高档组合 3 分")
	player.free()

func test_hud_city_title_colors_cover_every_actual_region_and_remain_unique() -> void:
	var used_colors: Dictionary[String, MapSection.REGION] = {}
	for region: MapSection.REGION in ResourceManager.地区非遗牌上限字典:
		assert_true(HUD.REGION_TITLE_COLORS.has(region), "%s 缺少对应牌框标题色" % MapSection.REGION.find_key(region))
		var color: Color = HUD.REGION_TITLE_COLORS.get(region, Color.BLACK)
		var color_key := color.to_html(false)
		assert_false(used_colors.has(color_key), "%s 的标题色与其他地区重复" % MapSection.REGION.find_key(region))
		used_colors[color_key] = region

func test_find_winner_keeps_score_ties() -> void:
	var first := PlayerClass.new()
	var second := PlayerClass.new()
	var third := PlayerClass.new()
	first.current_score = 7
	second.current_score = 12
	third.current_score = 12
	TurnManager.players.assign([first, second, third])
	var winners := ResourceManager.find_winner()
	assert_eq(winners.size(), 2)
	assert_true(winners.has(second))
	assert_true(winners.has(third))
	first.free()
	second.free()
	third.free()
