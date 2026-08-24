extends GutTest

var _first: PlayerClass
var _second: PlayerClass


func before_each() -> void:
	_first = PlayerClass.new()
	_first.player_name = "动画来源"
	_second = PlayerClass.new()
	_second.player_name = "动画目标"


func after_each() -> void:
	_first.free()
	_second.free()


func test_feiyi_gain_loss_and_transfer_emit_one_typed_visual_request_each() -> void:
	var card := 非遗牌.new()
	watch_signals(ResourceManager)

	assert_true(ResourceManager.add_feiyi_card(_first, card, false, true))
	assert_signal_emitted_with_parameters(ResourceManager, "card_hand_visual_requested", [ResourceManager.CardHandVisualKind.获得, _first, card, null, true])

	clear_signal_watcher()
	watch_signals(ResourceManager)
	assert_true(ResourceManager.transfer_feiyi_card(_first, _second, card))
	assert_signal_emitted_with_parameters(ResourceManager, "card_hand_visual_requested", [ResourceManager.CardHandVisualKind.转移, _first, card, _second, false])

	clear_signal_watcher()
	watch_signals(ResourceManager)
	assert_true(ResourceManager.remove_feiyi_card(_second, card, false))
	assert_signal_emitted_with_parameters(ResourceManager, "card_hand_visual_requested", [ResourceManager.CardHandVisualKind.失去, _second, card, null, false])


func test_food_and_retained_event_changes_use_the_same_animation_pipeline() -> void:
	var food := 食物牌.new()
	var event := 事件牌.new()
	watch_signals(ResourceManager)

	assert_true(ResourceManager.add_food_card(_first, food))
	assert_true(ResourceManager.remove_food_card(_first, food))
	assert_true(ResourceManager.add_event_card(_first, event))
	assert_true(ResourceManager.remove_event_card(_first, event))
	assert_signal_emit_count(ResourceManager, "card_hand_visual_requested", 4)


func test_food_hand_swap_emits_directional_transfer_for_every_actual_card() -> void:
	var first_food := 食物牌.new()
	var second_food := 食物牌.new()
	_first.食物牌手牌.append(first_food)
	_second.食物牌手牌.append(second_food)
	watch_signals(ResourceManager)

	assert_true(ResourceManager.swap_food_hands(_first, _second))

	assert_eq(_first.食物牌手牌, [second_food])
	assert_eq(_second.食物牌手牌, [first_food])
	assert_eq(get_signal_emit_count(ResourceManager, "card_hand_visual_requested"), 2)
	assert_eq(get_signal_parameters(ResourceManager, "card_hand_visual_requested", 0), [ResourceManager.CardHandVisualKind.转移, _first, first_food, _second, false])
	assert_eq(get_signal_parameters(ResourceManager, "card_hand_visual_requested", 1), [ResourceManager.CardHandVisualKind.转移, _second, second_food, _first, false])
