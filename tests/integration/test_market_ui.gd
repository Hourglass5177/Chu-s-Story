extends GutTest

var _panel: 研究所弹窗
var _player: PlayerClass
var _market_backup: Array[非遗牌]

func before_each() -> void:
	_market_backup = MarketManager.get_inventory()
	MarketManager.reset_for_new_game()
	_player = PlayerClass.new()
	_player.current_money = 1000
	_player.arrival_id = 4
	TurnManager.GameOn = true
	TurnManager.now_phase = TurnManager.TurnPhase.ACTION
	TurnManager.modal_resolution_depth = 0
	TurnManager.turn_timer.start(7.0)
	_panel = load("res://HUDs/研究所弹窗.tscn").instantiate() as 研究所弹窗
	add_child_autofree(_panel)

func after_each() -> void:
	TurnManager.turn_timer.stop()
	TurnManager.GameOn = false
	TurnManager.modal_resolution_depth = 0
	MarketManager.reset_for_new_game()
	for card: 非遗牌 in _market_backup:
		MarketManager.deposit_card(card, &"test_restore")
	_player.free()

func test_open_tabs_and_close_restore_full_action_timer() -> void:
	_panel.open_market(_player)
	assert_true(_panel.visible)
	assert_eq(TurnManager.modal_resolution_depth, 1)
	assert_true(TurnManager.turn_timer.is_stopped())
	assert_eq(_panel.balance_label.text, "余额  1000")
	assert_eq(_panel.purchase_label.text, "本次可购  3/3")
	assert_eq((_panel.card_grid.get_child(0) as Label).text, "暂无藏品")
	_panel._show_sell_page()
	assert_true(_panel.sell_tab.button_pressed)
	assert_false(_panel.buy_tab.button_pressed)
	_panel.close_market()
	assert_false(_panel.visible)
	assert_eq(TurnManager.modal_resolution_depth, 0)
	assert_gt(TurnManager.turn_timer.time_left, 14.0)
