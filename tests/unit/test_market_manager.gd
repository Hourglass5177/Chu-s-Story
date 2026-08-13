extends GutTest

var _inventory_backup: Array[非遗牌]
var _hud_backup: HUD

func before_each() -> void:
	_inventory_backup = MarketManager.get_inventory()
	_hud_backup = ResourceManager.hud
	ResourceManager.hud = null
	MarketManager.reset_for_new_game()

func after_each() -> void:
	MarketManager.reset_for_new_game()
	for card: 非遗牌 in _inventory_backup:
		MarketManager.deposit_card(card, &"test_restore")
	ResourceManager.hud = _hud_backup

func test_price_formula_and_national_filter() -> void:
	var card := _make_card("普通藏品", 非遗牌.CardCategory.神话传说, 2)
	assert_eq(MarketManager.get_sell_price(card), 350)
	assert_eq(MarketManager.get_buy_price(card), 700)
	var national := _make_card("国家级藏品", 非遗牌.CardCategory.国家级非遗, 5)
	assert_eq(MarketManager.get_sell_price(national), 0)
	assert_eq(MarketManager.get_buy_price(national), 0)
	assert_false(MarketManager.deposit_card(national))
	assert_true(MarketManager.get_inventory().is_empty())

func test_deposit_has_no_income_and_sale_then_repurchase_uses_double_price() -> void:
	var player := _make_player(1000)
	var discarded := _make_card("自动入库", 非遗牌.CardCategory.手工技艺, 1)
	assert_true(MarketManager.deposit_card(discarded, &"discard"))
	assert_eq(player.current_money, 1000)
	var card := _make_card("交易藏品", 非遗牌.CardCategory.神话传说, 2)
	player.非遗牌手牌.append(card)
	assert_true(MarketManager.sell_card(player, card))
	assert_eq(player.current_money, 1350)
	assert_true(MarketManager.buy_card(player, card, 8))
	assert_eq(player.current_money, 650)
	assert_true(player.非遗牌手牌.has(card))
	assert_eq(MarketManager.get_purchase_count(player, 8), 1)
	player.free()

func test_purchase_limit_is_per_arrival_and_sales_remain_available() -> void:
	var player := _make_player(10000)
	var cards: Array[非遗牌] = []
	for index in 4:
		var card := _make_card("藏品%d" % index, 非遗牌.CardCategory.戏曲表演, 0)
		cards.append(card)
		MarketManager.deposit_card(card, &"test")
	for index in 3:
		assert_true(MarketManager.buy_card(player, cards[index], 3))
	assert_eq(MarketManager.get_remaining_purchases(player, 3), 0)
	assert_false(MarketManager.buy_card(player, cards[3], 3))
	assert_true(MarketManager.sell_card(player, cards[0]), "达到购买上限后仍允许出售")
	assert_true(MarketManager.buy_card(player, cards[3], 4), "下一次真实到达使用独立购买额度")
	player.free()

func test_free_take_does_not_consume_visit_limit() -> void:
	var player := _make_player(0)
	var card := _make_card("免费藏品", 非遗牌.CardCategory.民间音乐, 0)
	MarketManager.deposit_card(card, &"test")
	assert_true(MarketManager.take_card_free(player, card))
	assert_eq(player.current_money, 0)
	assert_eq(MarketManager.get_purchase_count(player, 9), 0)
	player.free()

func test_visit_can_only_begin_once_for_same_real_arrival() -> void:
	var player := _make_player(1000)
	assert_false(MarketManager.can_open_visit(player, 0))
	assert_true(MarketManager.begin_visit(player, 1))
	assert_false(MarketManager.begin_visit(player, 1))
	assert_true(MarketManager.begin_visit(player, 2))
	MarketManager.reset_for_new_game()
	assert_true(MarketManager.can_open_visit(player, 1), "新游戏必须清除研究所访问状态")
	player.free()

func _make_player(money: int) -> PlayerClass:
	var player := PlayerClass.new()
	player.current_money = money
	return player

func _make_card(display_name: String, category: 非遗牌.CardCategory, score: int) -> 非遗牌:
	var card := 非遗牌.new()
	card.card_name = display_name
	card.category = category
	card.base_score = score
	return card
