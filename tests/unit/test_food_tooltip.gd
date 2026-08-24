extends GutTest

func test_tooltip_waits_point_six_seconds_while_paused_and_hides_on_exit() -> void:
	var tooltip := FoodTooltip.new()
	var target := Control.new()
	var card := 食物牌.new()
	card.effect_description = "测试食物效果"
	add_child_autofree(target)
	add_child_autofree(tooltip)
	await get_tree().process_frame
	tooltip.bind(target, card)
	tooltip._on_target_entered(target, card)
	get_tree().paused = true
	await get_tree().create_timer(0.65, true).timeout
	assert_true(tooltip.visible)
	assert_eq(tooltip._label.text, "测试食物效果")
	tooltip._on_target_exited(target)
	assert_false(tooltip.visible)
	get_tree().paused = false

func test_tooltip_adapts_to_content_instead_of_using_a_large_fixed_panel() -> void:
	var tooltip := FoodTooltip.new()
	var target := Control.new()
	var short_card := 食物牌.new()
	short_card.effect_description = "精力+3。"
	add_child_autofree(target)
	add_child_autofree(tooltip)
	await get_tree().process_frame

	tooltip._on_target_entered(target, short_card)
	tooltip._show_for_target()
	var short_size := tooltip.size
	assert_lte(short_size.x, 300.0, "短描述应使用紧凑宽度")
	assert_lte(short_size.y, 100.0, "单行描述不应撑成大竖框")

	var long_card := 食物牌.new()
	long_card.effect_description = "选择一名玩家，你与其精力各+1，且均跳过下个移动阶段和行动阶段。"
	tooltip._on_target_entered(target, long_card)
	tooltip._show_for_target()
	var long_size := tooltip.size
	assert_gt(long_size.x, short_size.x)
	assert_gt(long_size.y, short_size.y)
	assert_lte(long_size.x, FoodTooltip.MAX_PANEL_WIDTH)
	assert_eq(tooltip._label.text, long_card.effect_description)

func after_each() -> void:
	get_tree().paused = false
