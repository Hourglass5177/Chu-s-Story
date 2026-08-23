extends GutTest

const ACHIEVEMENT_DIR: String = "res://Cards/成就牌"

const EXPECTED: Dictionary[String, Dictionary] = {
	"游山玩水": {"id": &"you_shan_wan_shui", "score": 5, "threshold": 6},
	"饕餮": {"id": &"tao_tie", "score": 2, "threshold": 6},
	"大胃袋这一块": {"id": &"da_wei_dai", "score": 5, "threshold": 12},
	"野人": {"id": &"ye_ren", "score": 2, "threshold": 2},
	"超越人类": {"id": &"chao_yue_ren_lei", "score": 2, "threshold": 12},
	"幸运儿": {"id": &"xing_yun_er", "score": 3, "threshold": 5},
}


func test_six_active_achievement_resources_are_complete_and_unique() -> void:
	var ids: Dictionary[StringName, bool] = {}
	var loaded_count: int = 0
	for file_name: String in DirAccess.get_files_at(ACHIEVEMENT_DIR):
		if not file_name.ends_with(".tres"):
			continue
		var card: 成就牌 = ResourceLoader.load(ACHIEVEMENT_DIR.path_join(file_name)) as 成就牌
		assert_not_null(card, file_name)
		if card == null:
			continue
		loaded_count += 1
		assert_true(EXPECTED.has(card.card_name), "不应加载未确认成就：" + card.card_name)
		assert_false(ids.has(card.achievement_id), "achievement_id 不得重复")
		assert_eq(card.card_type, 卡牌基类.CardType.成就牌)
		assert_false(card.description.is_empty())
		assert_not_null(card.image_of_front)
		assert_not_null(card.image_of_back)
		var expected: Dictionary = EXPECTED[card.card_name]
		assert_eq(card.achievement_id, expected["id"])
		assert_eq(card.score_value, expected["score"])
		assert_eq(card.threshold, expected["threshold"])
		ids[card.achievement_id] = true
	assert_eq(loaded_count, 6)
	assert_false(FileAccess.file_exists(ACHIEVEMENT_DIR.path_join("守艺人.tres")))


func test_existing_faces_are_mapped_and_scenery_uses_shared_back_temporarily() -> void:
	var expected_faces: Dictionary[String, String] = {
		"幸运儿": "成就卡（牌面）1.png",
		"超越人类": "成就卡（牌面）2.png",
		"野人": "成就卡（牌面）3.png",
		"大胃袋这一块": "成就卡（牌面）4.png",
		"饕餮": "成就卡（牌面）5.png",
	}
	for card_name: String in expected_faces:
		var card: 成就牌 = ResourceLoader.load(ACHIEVEMENT_DIR.path_join(card_name + ".tres")) as 成就牌
		assert_eq(card.image_of_front.resource_path.get_file(), expected_faces[card_name])
		assert_eq(card.image_of_back.resource_path.get_file(), "成就卡（牌背）.png")
	var scenery: 成就牌 = ResourceLoader.load(ACHIEVEMENT_DIR.path_join("游山玩水.tres")) as 成就牌
	assert_eq(scenery.image_of_front.resource_path, scenery.image_of_back.resource_path)


func test_bottomless_stomach_declares_tao_tie_replacement() -> void:
	var upgrade: 成就牌 = ResourceLoader.load(ACHIEVEMENT_DIR.path_join("大胃袋这一块.tres")) as 成就牌
	assert_eq(upgrade.replaces_achievement_id, AchievementManager.ID_TAO_TIE)
