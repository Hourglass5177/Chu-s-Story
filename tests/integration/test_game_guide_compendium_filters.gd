extends GutTest

## Behavioural contracts for the guide's faceted compendium and image-preview
## affordances.  Selections are derived from live Resource data so adding cards,
## categories or regions does not make these tests stale.

const GUIDE_SCENE := preload("res://UI/GameGuide/digital_game_guide.tscn")
const TEST_DISCOVERY_PATH := "user://guide-filter-test.cfg"

var _guide: DigitalGameGuide
var _paused_backup: bool
var _storage_backup: String
var _test_storage_enabled_backup: bool
var _discovered_backup: Dictionary
var _game_on_backup: bool


func before_each() -> void:
	_paused_backup = get_tree().paused
	get_tree().paused = false
	_storage_backup = DiscoveryManager._storage_path
	_test_storage_enabled_backup = DiscoveryManager._test_storage_enabled
	_discovered_backup = DiscoveryManager._discovered.duplicate(true)
	_game_on_backup = TurnManager.GameOn
	TurnManager.GameOn = false
	_remove_discovery_file()
	DiscoveryManager.configure_storage_path(TEST_DISCOVERY_PATH)
	_discover_every_known_entry()
	_guide = GUIDE_SCENE.instantiate() as DigitalGameGuide
	add_child_autofree(_guide)
	await get_tree().process_frame


func after_each() -> void:
	if _guide != null and _guide.is_guide_open():
		_guide.close_guide(false)
	_remove_discovery_file()
	DiscoveryManager._storage_path = _storage_backup
	DiscoveryManager._test_storage_enabled = _test_storage_enabled_backup
	DiscoveryManager._discovered = _discovered_backup.duplicate(true)
	TurnManager.GameOn = _game_on_backup
	get_tree().paused = _paused_backup


func test_feiyi_regions_and_categories_use_or_inside_each_facet_and_and_between_facets() -> void:
	assert_true(_guide.open_guide(GuideOpenContext.new(), false))
	var records := _entry_records(DiscoveryManager.KIND_FEIYI, [&"region_value", &"category_value"])
	var selection := _find_two_by_two_selection(records, &"region_value", &"category_value")
	assert_false(selection.is_empty(), "实际非遗资源应能提供覆盖两个地区、两个类别的筛选样本")
	if selection.is_empty():
		return

	_guide.call(&"_render_compendium", DiscoveryManager.KIND_FEIYI, 1)
	for value: int in selection.first_values:
		_guide.call(&"_toggle_compendium_filter", &"feiyi_region", StringName(str(value)), true, DiscoveryManager.KIND_FEIYI)
	for value: int in selection.second_values:
		_guide.call(&"_toggle_compendium_filter", &"feiyi_category", StringName(str(value)), true, DiscoveryManager.KIND_FEIYI)

	var actual: Array[StringName] = _guide.call(&"_get_filtered_compendium_ids", DiscoveryManager.KIND_FEIYI)
	var expected := _expected_ids_for_facets(records, {
		&"region_value": selection.first_values,
		&"category_value": selection.second_values,
	})
	assert_eq(actual, expected, "地区栏内应取并集、类别栏内应取并集，两栏之间再取交集")
	assert_eq((_guide.get("_compendium_filters") as Dictionary)[&"feiyi_region"].size(), 2)
	assert_eq((_guide.get("_compendium_filters") as Dictionary)[&"feiyi_category"].size(), 2)
	assert_eq(int(_guide.get("_compendium_page")), 0, "修改筛选后必须回到第一页")
	assert_eq(_values_present(actual, DiscoveryManager.KIND_FEIYI, &"region_value"), _as_value_set(selection.first_values))
	assert_eq(_values_present(actual, DiscoveryManager.KIND_FEIYI, &"category_value"), _as_value_set(selection.second_values))


func test_food_level_filter_returns_the_union_of_all_selected_levels() -> void:
	assert_true(_guide.open_guide(GuideOpenContext.new(), false))
	var records := _entry_records(DiscoveryManager.KIND_FOOD, [&"level_value"])
	var levels := _unique_values(records, &"level_value")
	assert_gte(levels.size(), 2, "食物资源至少应包含两个可筛选级别")
	if levels.size() < 2:
		return
	var selected: Array[int] = [levels[0], levels[1]]
	for level: int in selected:
		_guide.call(&"_toggle_compendium_filter", &"food_level", StringName(str(level)), true, DiscoveryManager.KIND_FOOD)
	var actual: Array[StringName] = _guide.call(&"_get_filtered_compendium_ids", DiscoveryManager.KIND_FOOD)
	var expected := _expected_ids_for_facets(records, {&"level_value": selected})
	assert_eq(actual, expected)
	assert_eq(_values_present(actual, DiscoveryManager.KIND_FOOD, &"level_value"), _as_value_set(selected))


func test_scenery_region_filter_allows_multiple_regions_at_once() -> void:
	assert_true(_guide.open_guide(GuideOpenContext.new(), false))
	var records := _entry_records(DiscoveryManager.KIND_SCENERY, [&"region_value"])
	var regions := _unique_values(records, &"region_value")
	assert_gte(regions.size(), 2, "风景资源至少应包含两个可筛选地区")
	if regions.size() < 2:
		return
	var selected: Array[int] = [regions[0], regions[1]]
	for region: int in selected:
		_guide.call(&"_toggle_compendium_filter", &"scenery_region", StringName(str(region)), true, DiscoveryManager.KIND_SCENERY)
	var actual: Array[StringName] = _guide.call(&"_get_filtered_compendium_ids", DiscoveryManager.KIND_SCENERY)
	var expected := _expected_ids_for_facets(records, {&"region_value": selected})
	assert_eq(actual, expected)
	assert_eq(_values_present(actual, DiscoveryManager.KIND_SCENERY, &"region_value"), _as_value_set(selected))


func test_changing_any_paginated_compendium_filter_resets_to_page_zero() -> void:
	assert_true(_guide.open_guide(GuideOpenContext.new(), false))
	var cases: Array[Dictionary] = [
		{"kind": DiscoveryManager.KIND_FEIYI, "state": &"feiyi_region", "field": &"region_value"},
		{"kind": DiscoveryManager.KIND_FOOD, "state": &"food_level", "field": &"level_value"},
		{"kind": DiscoveryManager.KIND_SCENERY, "state": &"scenery_region", "field": &"region_value"},
	]
	var exercised := 0
	for test_case: Dictionary in cases:
		var kind := StringName(test_case.kind)
		var known_ids := DiscoveryManager.get_known_ids(kind)
		if known_ids.size() <= DigitalGameGuide.PAGE_SIZE:
			continue
		_guide.call(&"_render_compendium", kind, 1)
		assert_eq(int(_guide.get("_compendium_page")), 1, "%s 的测试前置必须确实位于第二页" % kind)
		var options: Array[Dictionary] = _guide.call(&"_get_compendium_filter_options", kind, StringName(test_case.field))
		assert_false(options.is_empty())
		if options.is_empty():
			continue
		_guide.call(
			&"_toggle_compendium_filter",
			StringName(test_case.state),
			StringName(options[0].key),
			true,
			kind
		)
		assert_eq(int(_guide.get("_compendium_page")), 0, "%s 修改筛选后必须回到第一页" % kind)
		_guide.call(&"_clear_compendium_filters", kind)
		exercised += 1
	assert_gte(exercised, 2, "至少应对两个拥有多页内容的图鉴验证页码重置")


func test_every_rule_media_preview_button_has_no_tooltip_and_still_opens_the_large_preview() -> void:
	assert_true(_guide.open_guide(GuideOpenContext.new(), false))
	var counts := {&"manual": 0, &"demo": 0}
	var opened := {&"manual": false, &"demo": false}
	for destination: Dictionary in _all_media_destinations():
		_render_destination(destination)
		await _settle_layout()
		for node: Node in _descendants(_guide.get_node("%Article")):
			var component_kind := &""
			if node is ManualMediaBlock:
				component_kind = &"manual"
			elif node is GuideVisualDemo:
				component_kind = &"demo"
			else:
				continue
			var expected_name := "ManualMediaPreviewButton" if component_kind == &"manual" else "GuideMediaPreviewButton"
			var component_buttons: Array[Button] = []
			for descendant: Node in _descendants(node):
				if descendant is Button and descendant.name == expected_name:
					component_buttons.append(descendant as Button)
			assert_false(component_buttons.is_empty(), "%s 必须为可见小图提供放大入口" % node.get_class())
			for button: Button in component_buttons:
				counts[component_kind] = int(counts[component_kind]) + 1
				assert_eq(button.tooltip_text, "", "%s 不应再显示冗余悬浮文字" % button.name)
				assert_false(button.disabled)
				assert_eq(button.focus_mode, Control.FOCUS_ALL)
				assert_eq(button.accessibility_name, "查看大图")
				assert_false(button.accessibility_description.is_empty(), "移除 Tooltip 后仍须保留无障碍图像说明")
				assert_gt(button.pressed.get_connections().size(), 0, "%s 必须仍连接放大交互" % button.name)
				if not bool(opened[component_kind]):
					button.pressed.emit()
					await get_tree().process_frame
					var preview := _guide.get_node("%MediaPreview") as Control
					assert_true(preview.visible, "%s 点击后必须打开大图" % button.name)
					assert_not_null((_guide.get_node("%MediaPreviewImage") as TextureRect).texture)
					_guide.call(&"_close_media_preview")
					await get_tree().process_frame
					opened[component_kind] = true
	assert_gt(int(counts[&"manual"]), 0, "测试必须覆盖 ManualMediaBlock")
	assert_gt(int(counts[&"demo"]), 0, "测试必须覆盖 GuideVisualDemo")
	assert_true(bool(opened[&"manual"]))
	assert_true(bool(opened[&"demo"]))


func _entry_records(kind: StringName, fields: Array[StringName]) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for entry_id: StringName in DiscoveryManager.get_known_ids(kind):
		var data: Dictionary = _guide.call(&"_get_entry_data", kind, entry_id)
		var record: Dictionary = {&"id": entry_id}
		var complete := true
		for field: StringName in fields:
			var value := int(data.get(field, -1))
			if value < 0:
				complete = false
				break
			record[field] = value
		if complete:
			records.append(record)
	return records


func _find_two_by_two_selection(records: Array[Dictionary], first_field: StringName, second_field: StringName) -> Dictionary:
	var first_values := _unique_values(records, first_field)
	var second_values := _unique_values(records, second_field)
	for first_a_index: int in range(first_values.size()):
		for first_b_index: int in range(first_a_index + 1, first_values.size()):
			var selected_first: Array[int] = [first_values[first_a_index], first_values[first_b_index]]
			for second_a_index: int in range(second_values.size()):
				for second_b_index: int in range(second_a_index + 1, second_values.size()):
					var selected_second: Array[int] = [second_values[second_a_index], second_values[second_b_index]]
					var matching := _matching_records(records, {
						first_field: selected_first,
						second_field: selected_second,
					})
					if _record_values(matching, first_field).size() == 2 and _record_values(matching, second_field).size() == 2:
						return {"first_values": selected_first, "second_values": selected_second}
	return {}


func _matching_records(records: Array[Dictionary], facets: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Dictionary in records:
		var matches := true
		for field: StringName in facets:
			if not (facets[field] as Array).has(int(record.get(field, -1))):
				matches = false
				break
		if matches:
			result.append(record)
	return result


func _expected_ids_for_facets(records: Array[Dictionary], facets: Dictionary) -> Array[StringName]:
	var result: Array[StringName] = []
	for record: Dictionary in _matching_records(records, facets):
		result.append(StringName(record.id))
	return result


func _unique_values(records: Array[Dictionary], field: StringName) -> Array[int]:
	var unique: Dictionary = {}
	for record: Dictionary in records:
		unique[int(record.get(field, -1))] = true
	var result: Array[int] = []
	for value: Variant in unique.keys():
		result.append(int(value))
	result.sort()
	return result


func _record_values(records: Array[Dictionary], field: StringName) -> Dictionary:
	var result: Dictionary = {}
	for record: Dictionary in records:
		result[int(record.get(field, -1))] = true
	return result


func _values_present(ids: Array[StringName], kind: StringName, field: StringName) -> Dictionary:
	var result: Dictionary = {}
	for entry_id: StringName in ids:
		var data: Dictionary = _guide.call(&"_get_entry_data", kind, entry_id)
		result[int(data.get(field, -1))] = true
	return result


func _as_value_set(values: Array[int]) -> Dictionary:
	var result: Dictionary = {}
	for value: int in values:
		result[value] = true
	return result


func _all_media_destinations() -> Array[Dictionary]:
	var result: Array[Dictionary] = [{"kind": &"home"}]
	var catalog := _guide.get("_catalog") as ManualCatalog
	for topic: ManualTopic in catalog.get_topics():
		if topic.category == &"quick":
			result.append({"kind": &"topic", "topic_id": topic.topic_id, "group_id": &""})
		else:
			for group: Dictionary in topic.groups:
				result.append({
					"kind": &"topic",
					"topic_id": topic.topic_id,
					"group_id": StringName(group.get("id", &"")),
				})
	return result


func _render_destination(destination: Dictionary) -> void:
	if StringName(destination.kind) == &"home":
		_guide.call(&"_render_home")
	else:
		_guide.call(&"_render_topic", StringName(destination.topic_id), StringName(destination.group_id))


func _settle_layout() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _discover_every_known_entry() -> void:
	for kind: StringName in [
		DiscoveryManager.KIND_FOOD,
		DiscoveryManager.KIND_EVENT,
		DiscoveryManager.KIND_ACHIEVEMENT,
	]:
		for entry_id: StringName in DiscoveryManager.get_known_ids(kind):
			DiscoveryManager.record_discovery(kind, entry_id)


func _descendants(root: Node) -> Array[Node]:
	var result: Array[Node] = []
	var pending: Array[Node] = []
	for child: Node in root.get_children():
		pending.append(child)
	while not pending.is_empty():
		var node := pending.pop_front() as Node
		result.append(node)
		for child: Node in node.get_children():
			pending.append(child)
	return result


func _remove_discovery_file() -> void:
	if FileAccess.file_exists(TEST_DISCOVERY_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_DISCOVERY_PATH))
