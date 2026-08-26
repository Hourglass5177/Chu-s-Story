extends GutTest


func test_generated_catalog_has_stable_unique_topics_and_valid_relations() -> void:
	var catalog := ManualCatalog.load_generated()
	assert_true(catalog.validate().is_empty())
	assert_ne(catalog.source_sha256, "")
	var all_topics := catalog.get_topics()
	assert_eq(all_topics.size(), 18)
	assert_eq(catalog.get_topics(&"quick").size(), 6)
	assert_eq(catalog.get_topics(&"rules").size(), 12)
	var ids: Dictionary = {}
	for topic: ManualTopic in all_topics:
		assert_false(ids.has(topic.topic_id), "主题 ID 必须唯一：%s" % topic.topic_id)
		ids[topic.topic_id] = true


func test_catalog_search_uses_titles_keywords_and_body_copy() -> void:
	var catalog := ManualCatalog.load_generated()
	assert_true(catalog.search("响应链", &"rules").any(func(topic: ManualTopic) -> bool: return topic.topic_id == &"event_response"))
	assert_true(catalog.search("江汉三市", &"rules").any(func(topic: ManualTopic) -> bool: return topic.topic_id == &"scoring_victory"))
	assert_true(catalog.search("不存在的规则词", &"rules").is_empty())


func test_all_guide_context_kinds_resolve_to_existing_topics() -> void:
	var scene := preload("res://UI/GameGuide/digital_game_guide.tscn") as PackedScene
	var guide := scene.instantiate() as DigitalGameGuide
	add_child_autofree(guide)
	await get_tree().process_frame
	var catalog: ManualCatalog = guide.get("_catalog") as ManualCatalog
	for kind: StringName in [
		DiscoveryManager.KIND_FEIYI,
		DiscoveryManager.KIND_FOOD,
		DiscoveryManager.KIND_EVENT,
		DiscoveryManager.KIND_ACHIEVEMENT,
		DiscoveryManager.KIND_PROFESSION,
		DiscoveryManager.KIND_SCENERY,
		&"map_section",
		&"market",
		&"score",
		&"phase",
	]:
		var topic_id: StringName = guide.call(&"_topic_for_kind", kind)
		assert_true(catalog.has_topic(topic_id), "%s 必须映射到有效指南主题" % kind)

