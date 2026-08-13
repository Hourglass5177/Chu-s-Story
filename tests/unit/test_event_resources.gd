extends GutTest

const EVENT_DIR := "res://Cards/事件牌"
const BLOCKED_NAMES := ["孤注一掷"]
const RETAINED_NAMES := ["妙手回春", "游目骋怀", "畅行无阻", "金蝉脱壳", "移花接木"]

func test_all_40_event_resources_are_valid_and_uniquely_identified() -> void:
	var files := DirAccess.get_files_at(EVENT_DIR)
	var resources: Array[事件牌] = []
	var ids: Dictionary[StringName, bool] = {}
	for file_name: String in files:
		if not file_name.ends_with(".tres"):
			continue
		var card := load(EVENT_DIR + "/" + file_name) as 事件牌
		assert_not_null(card, file_name + " 必须能加载为事件牌")
		resources.append(card)
		assert_false(card.event_id.is_empty(), file_name + " 必须有稳定 event_id")
		assert_false(ids.has(card.event_id), "event_id 不得重复：" + str(card.event_id))
		assert_eq(card.card_type, 卡牌基类.CardType.事件牌, file_name + " 的卡牌类型必须为事件牌")
		assert_false(card.card_name.is_empty(), file_name + " 必须有牌名")
		assert_false(card.description.is_empty(), file_name + " 必须有正式描述")
		assert_not_null(card.image_of_front, file_name + " 必须有牌面")
		assert_not_null(card.image_of_back, file_name + " 必须有牌背")
		ids[card.event_id] = true
	assert_eq(resources.size(), 40)

func test_exactly_39_events_are_active_and_all_have_effect_dispatch() -> void:
	var active_count := 0
	var active_ids: Array[StringName] = []
	for file_name: String in DirAccess.get_files_at(EVENT_DIR):
		if not file_name.ends_with(".tres"):
			continue
		var card := load(EVENT_DIR + "/" + file_name) as 事件牌
		if card.is_available():
			active_count += 1
			active_ids.append(card.event_id)
			assert_true(EventManager.is_event_implemented(card.event_id), card.card_name + " 缺少效果分派")
	assert_eq(active_count, 39)
	assert_eq(EventManager.IMPLEMENTED_EVENT_IDS.size(), 39)
	for event_id: StringName in EventManager.IMPLEMENTED_EVENT_IDS:
		assert_has(active_ids, event_id, str(event_id) + " 不得只登记分派而没有可用资源")

func test_dependency_events_are_explicitly_blocked() -> void:
	for name: String in BLOCKED_NAMES:
		var card := load(EVENT_DIR + "/" + name + ".tres") as 事件牌
		assert_false(card.is_available(), name + " 不应进入当前牌库")
		assert_false(card.dependency_note.is_empty(), name + " 必须写明依赖")

func test_only_confirmed_five_events_are_retainable() -> void:
	var retained: Array[String] = []
	for file_name: String in DirAccess.get_files_at(EVENT_DIR):
		if file_name.ends_with(".tres"):
			var card := load(EVENT_DIR + "/" + file_name) as 事件牌
			if card.retainable:
				retained.append(card.card_name)
	retained.sort()
	var expected := RETAINED_NAMES.duplicate()
	expected.sort()
	assert_eq(retained, expected)

func test_runtime_event_deck_filters_blocked_cards() -> void:
	assert_eq(ResourceManager.事件牌库.size(), 39)
	for card: 事件牌 in ResourceManager.事件牌库:
		assert_true(card.is_available())

func test_four_market_events_use_versioned_digital_card_faces() -> void:
	var names := ["鉴往知来", "釜底抽薪", "展艺共研", "市集淘珍"]
	var expected_size := Vector2i.ZERO
	for event_name: String in names:
		var card := load(EVENT_DIR + "/" + event_name + ".tres") as 事件牌
		assert_true(card.is_available())
		assert_string_contains(card.image_of_front.resource_path, "/数字版/")
		assert_string_contains(card.image_of_front.resource_path, "_v2.png")
		var size := Vector2i(card.image_of_front.get_width(), card.image_of_front.get_height())
		assert_gt(size.y, size.x, event_name + " 必须保持竖版牌面")
		if expected_size == Vector2i.ZERO:
			expected_size = size
		else:
			assert_lte(absi(size.x - expected_size.x), 1, "四张数字版牌面宽度差不得超过1像素")
			assert_lte(absi(size.y - expected_size.y), 1, "四张数字版牌面高度差不得超过1像素")

func test_discarded_event_does_not_return_to_draw_pile() -> void:
	var deck_before := ResourceManager.事件牌库.duplicate()
	var discard_before := ResourceManager.事件弃牌堆.duplicate()
	var player := PlayerClass.new()
	var card := ResourceManager.draw_event_card(player)
	assert_not_null(card)
	ResourceManager.discard_event(card)
	assert_false(ResourceManager.事件牌库.has(card))
	assert_true(ResourceManager.事件弃牌堆.has(card))
	ResourceManager.事件牌库.assign(deck_before)
	ResourceManager.事件弃牌堆.assign(discard_before)
	player.free()
