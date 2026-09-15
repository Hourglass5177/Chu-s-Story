extends GutTest

const TEST_PATH: String = "user://test_heritage_avatar_context.cfg"
const GALLERY := preload("res://UI/GameGuide/components/minigame_gallery.tscn")


func before_each() -> void:
	HeritageMinigamePreferences.configure_storage_path(TEST_PATH)
	_remove_test_preferences()


func after_each() -> void:
	_remove_test_preferences()
	HeritageMinigamePreferences.configure_storage_path()


func test_formal_run_snapshots_each_actual_profession_identity() -> void:
	var player := PlayerClass.new()
	for profession: ProfessionDefinition in ProfessionManager.get_all_definitions():
		player.player_types = profession.profession_type
		var context := HeritageTaskRunContext.new(&"xia_lian_dan_shu", player)
		assert_eq(context.avatar_id, profession.profession_id)
		assert_false(context.practice_mode)
	player.free()


func test_snapshot_keeps_start_identity_after_profession_or_practice_changes() -> void:
	var player := PlayerClass.new()
	player.player_types = PlayerClass.PlayerCharacter.商业博主
	var context := HeritageTaskRunContext.new(&"xia_lian_dan_shu", player, null, 2, 5, 73)
	player.player_types = PlayerClass.PlayerCharacter.生活博主
	HeritageMinigamePreferences.save_practice_avatar(&"magic_blogger")
	var snapshot := context.duplicate_snapshot()
	assert_eq(context.avatar_id, &"business_blogger")
	assert_eq(snapshot.avatar_id, &"business_blogger")
	assert_eq(snapshot.random_seed, 73)
	assert_eq(snapshot.rng.randi(), context.rng.randi(), "外观不改变随机序列")
	player.free()


func test_practice_choice_persists_without_overwriting_tutorial_or_calibration() -> void:
	HeritageMinigamePreferences.complete_tutorial(&"han_ju", 4)
	HeritageMinigamePreferences.save_offset(82)
	assert_true(HeritageMinigamePreferences.save_practice_avatar(&"adventure_blogger"))
	var saved := ConfigFile.new()
	assert_eq(saved.load(TEST_PATH), OK)
	assert_eq(saved.get_value("appearance", "practice_avatar_id"), "adventure_blogger")
	assert_true(HeritageMinigamePreferences.tutorial_done(&"han_ju", 4))
	assert_eq(HeritageMinigamePreferences.offset_ms(), 82)
	var context := HeritageTaskRunContext.new(&"han_ju", null, null, 0, 0, 1, true)
	assert_eq(context.avatar_id, &"adventure_blogger")
	HeritageMinigamePreferences.save_practice_avatar(&"food_blogger")
	assert_eq(context.duplicate_snapshot().avatar_id, &"adventure_blogger")
	assert_null(context.player)
	assert_null(context.card)


func test_missing_old_or_invalid_preference_falls_back_to_travel() -> void:
	assert_eq(HeritageMinigamePreferences.practice_avatar_id(), &"travel_blogger")
	var config := ConfigFile.new()
	config.set_value("appearance", "practice_avatar_id", "not_a_blogger")
	assert_eq(config.save(TEST_PATH), OK)
	assert_eq(HeritageMinigamePreferences.practice_avatar_id(), &"travel_blogger")
	config.set_value("appearance", "practice_avatar_id", ["invalid type"])
	assert_eq(config.save(TEST_PATH), OK)
	assert_eq(HeritageMinigamePreferences.practice_avatar_id(), &"travel_blogger")
	assert_false(HeritageMinigamePreferences.save_practice_avatar(&"invalid"))


func test_music_assistance_defaults_on_and_saves_separately() -> void:
	assert_true(HeritageMinigamePreferences.visual_assistance_enabled())
	HeritageMinigamePreferences.save_practice_avatar(&"life_blogger")
	assert_true(HeritageMinigamePreferences.save_visual_assistance(false))
	assert_false(HeritageMinigamePreferences.visual_assistance_enabled())
	assert_eq(HeritageMinigamePreferences.practice_avatar_id(), &"life_blogger")


func test_missing_or_mismatched_appearance_never_substitutes_another_blogger() -> void:
	var presentation := HeritageTaskPresentation.new()
	var travel := HeritageAvatarAppearance.new()
	travel.avatar_id = &"travel_blogger"
	presentation.avatar_appearances[&"travel_blogger"] = travel
	presentation.avatar_appearances[&"life_blogger"] = travel
	assert_same(presentation.get_appearance(&"travel_blogger"), travel)
	assert_null(presentation.get_appearance(&"life_blogger"))
	assert_null(presentation.get_appearance(&"magic_blogger"))


func test_presentation_cover_is_optional_and_does_not_replace_original_file() -> void:
	var definition := HeritageTaskDefinition.new()
	var original := GradientTexture2D.new()
	var pixel_cover := GradientTexture2D.new()
	definition.gallery_thumbnail = original
	assert_same(definition.get_gallery_thumbnail(), original)
	definition.presentation = HeritageTaskPresentation.new()
	assert_same(definition.get_gallery_thumbnail(), original)
	definition.presentation.cover = pixel_cover
	assert_same(definition.get_gallery_thumbnail(), pixel_cover)
	assert_same(definition.gallery_thumbnail, original)


func test_gallery_exposes_all_six_choices_and_emits_selected_identity() -> void:
	var gallery := GALLERY.instantiate() as GuideMinigameGallery
	add_child_autofree(gallery)
	var avatars: Array[Dictionary] = []
	for avatar_id: StringName in HeritageAvatarCatalog.IDS:
		avatars.append({"avatar_id": avatar_id})
	gallery.configure([], false, &"business_blogger", avatars)
	var selector := gallery.get_node("PracticeAvatarSelector")
	assert_eq(selector.get_child_count(), 6)
	var business := selector.get_node("Avatar_business_blogger") as Button
	assert_true(business.button_pressed)
	watch_signals(gallery)
	var life := selector.get_node("Avatar_life_blogger") as Button
	life.pressed.emit()
	assert_eq(gallery.get_selected_avatar_id(), &"life_blogger")
	assert_signal_emitted_with_parameters(gallery, "avatar_selected", [&"life_blogger"])
	assert_false(FileAccess.file_exists(TEST_PATH), "展示组件不直接写本机存档")


func _remove_test_preferences() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
