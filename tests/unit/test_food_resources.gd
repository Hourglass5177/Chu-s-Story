extends GutTest

func test_sixty_food_resources_have_unique_ids_levels_prices_and_faces() -> void:
	var files := DirAccess.get_files_at("res://Cards/食物牌")
	var cards: Array[食物牌] = []
	var ids: Dictionary[StringName, bool] = {}
	var counts := {食物牌.FoodType.市级: 0, 食物牌.FoodType.省级: 0, 食物牌.FoodType.国家级: 0}
	for file_name: String in files:
		if not file_name.ends_with(".tres"):
			continue
		var card := load("res://Cards/食物牌/%s" % file_name) as 食物牌
		assert_not_null(card, file_name)
		if card == null:
			continue
		cards.append(card)
		assert_false(card.food_id.is_empty(), card.card_name)
		assert_false(ids.has(card.food_id), str(card.food_id))
		ids[card.food_id] = true
		assert_not_null(card.image_of_front, card.card_name)
		assert_not_null(card.image_of_back, card.card_name)
		assert_false(card.effect_description.is_empty(), card.card_name)
		assert_eq(card.cost, card.get_default_cost(), card.card_name)
		counts[card.food_type] = int(counts.get(card.food_type, 0)) + 1
		if card.food_type != 食物牌.FoodType.市级:
			assert_string_contains(card.image_of_front.resource_path, "/完全版-v2/", card.card_name)
	assert_eq(cards.size(), 60)
	assert_eq(counts[食物牌.FoodType.市级], 20)
	assert_eq(counts[食物牌.FoodType.省级], 36)
	assert_eq(counts[食物牌.FoodType.国家级], 4)

func test_every_high_level_food_has_an_effect_dispatch() -> void:
	var found: Dictionary[StringName, bool] = {}
	for file_name: String in DirAccess.get_files_at("res://Cards/食物牌"):
		if not file_name.ends_with(".tres"):
			continue
		var food := load("res://Cards/食物牌/%s" % file_name) as 食物牌
		if food != null and food.food_type != 食物牌.FoodType.市级:
			assert_true(food.food_id in FoodManager.IMPLEMENTED_FOOD_IDS, food.card_name)
			found[food.food_id] = true
	assert_eq(found.size(), 40)
	assert_eq(FoodManager.IMPLEMENTED_FOOD_IDS.size(), 40)


func test_mao_zui_keeps_card_copy_verbatim_and_exposes_its_digital_ruling_separately() -> void:
	var card := load("res://Cards/食物牌/毛嘴卤鸡.tres") as 食物牌
	assert_not_null(card)
	assert_eq(card.effect_description, "所有玩家精力+1并支付你100积分点。")
	assert_eq(card.ruling_note, "余额不足时支付当前全部余额，仍然精力+1。")

func test_high_level_resource_copy_matches_the_formal_food_table_verbatim() -> void:
	var source := FileAccess.get_file_as_string("res://docs/食物牌效果与价格表（省级与国家级）.md")
	var expected: Dictionary[String, Dictionary] = {}
	for line: String in source.split("\n"):
		if not line.begins_with("|"):
			continue
		var columns := line.split("|", false)
		if columns.size() < 4:
			continue
		var card_name := columns[0].strip_edges()
		var description := columns[1].strip_edges()
		var price_text := columns[2].strip_edges()
		if not price_text.is_valid_int():
			continue
		expected[card_name] = {
			"description": description,
			"price": price_text.to_int(),
		}

	assert_eq(expected.size(), 40, "正式策划表必须包含40张省级/国家级食物")
	var checked := 0
	for file_name: String in DirAccess.get_files_at("res://Cards/食物牌"):
		if not file_name.ends_with(".tres"):
			continue
		var card := load("res://Cards/食物牌/%s" % file_name) as 食物牌
		if card == null or card.food_type == 食物牌.FoodType.市级:
			continue
		assert_true(expected.has(card.card_name), "%s 必须使用策划表正名" % card.card_name)
		if not expected.has(card.card_name):
			continue
		var row: Dictionary = expected[card.card_name]
		assert_eq(card.effect_description, str(row["description"]), "%s 的效果描述不得改写" % card.card_name)
		assert_eq(card.description, str(row["description"]), "%s 的通用描述不得保留另一套文案" % card.card_name)
		assert_eq(card.cost, int(row["price"]), "%s 的价格必须与策划表一致" % card.card_name)
		checked += 1
	assert_eq(checked, 40)

func test_v2_face_manifest_keeps_exact_copy_and_adaptive_readable_type() -> void:
	var manifest_path := "res://arts/食物牌/数字版/完全版-v2/manifest.json"
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	assert_true(parsed is Array)
	if not parsed is Array:
		return
	var rows: Array = parsed
	assert_eq(rows.size(), 40)
	var expected := {}
	for line: String in FileAccess.get_file_as_string("res://docs/食物牌效果与价格表（省级与国家级）.md").split("\n"):
		if not line.begins_with("|"):
			continue
		var columns := line.split("|", false)
		if columns.size() >= 4 and columns[2].strip_edges().is_valid_int():
			expected[columns[0].strip_edges()] = columns[1].strip_edges()
	for row: Dictionary in rows:
		var name := str(row.get("name", ""))
		assert_eq(str(row.get("description", "")), str(expected.get(name, "")), name)
		assert_between(int(row.get("font_size", 0)), 32, 42, name)
		assert_between(int(row.get("line_count", 0)), 1, 3, name)
		assert_true(FileAccess.file_exists("res://arts/食物牌/数字版/完全版-v2/%s" % row.get("output", "")), name)
	assert_true(FileAccess.file_exists(ProjectSettings.globalize_path("res://docs/牌面验收/食物牌v2总览.png")))
	assert_true(FileAccess.file_exists(ProjectSettings.globalize_path("res://docs/牌面验收/食物牌v2总览-100%.png")))

func test_filtered_draw_preserves_unmatched_relative_order() -> void:
	var city_a := _food(&"city_a", 食物牌.FoodType.市级)
	var national := _food(&"national", 食物牌.FoodType.国家级)
	var city_b := _food(&"city_b", 食物牌.FoodType.市级)
	var provincial := _food(&"provincial", 食物牌.FoodType.省级)
	var backup := ResourceManager.食物牌库.duplicate()
	ResourceManager.食物牌库.assign([city_a, national, city_b, provincial])
	var drawn := ResourceManager.draw_food_cards_filtered(2, [食物牌.FoodType.市级])
	assert_eq(drawn, [city_b, city_a])
	assert_eq(ResourceManager.食物牌库, [national, provincial])
	ResourceManager.食物牌库.assign(backup)

func _food(id: StringName, level: 食物牌.FoodType) -> 食物牌:
	var card := 食物牌.new()
	card.food_id = id
	card.food_type = level
	card.cost = card.get_default_cost()
	return card
