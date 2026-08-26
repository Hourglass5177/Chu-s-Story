extends GutTest

const MAIN_MAP_SCRIPT: Script = preload("res://main_map.gd")

var _player_data_backup: Array = []
var _active_setup_backup: SessionSetup = null
var _prepared_backup: bool = false
var _target_score_backup: int = SessionSetup.DEFAULT_TARGET_SCORE


func before_each() -> void:
	_player_data_backup = GameManager.player_data.duplicate(true)
	_active_setup_backup = GameManager._active_session_setup
	_prepared_backup = GameManager._local_session_prepared
	_target_score_backup = GameManager._configured_target_score
	GameManager.player_data.clear()
	GameManager._active_session_setup = null
	GameManager._local_session_prepared = false


func after_each() -> void:
	GameManager.player_data = _player_data_backup.duplicate(true)
	GameManager._active_session_setup = _active_setup_backup
	GameManager._local_session_prepared = _prepared_backup
	GameManager._configured_target_score = _target_score_backup


func test_resize_slots_preserves_existing_players_and_defaults_new_bots() -> void:
	var setup := SessionSetup.new()
	var first_player: PlayerSetup = setup.players[0]
	first_player.display_name = "阿楚"
	first_player.profession_type = PlayerClass.PlayerCharacter.旅行博主
	first_player.starting_region = MapSection.REGION.恩施

	assert_eq(setup.resize_slots(1, 2), OK)
	assert_same(setup.players[0], first_player)
	assert_eq(setup.players[0].display_name, "阿楚")
	assert_eq(setup.players[1].display_name, "电脑1")
	assert_eq(setup.players[2].display_name, "电脑2")
	assert_true(setup.players[1].is_bot())
	assert_true(setup.players[2].is_bot())
	assert_ne(setup.players[1].profession_type, setup.players[2].profession_type)
	assert_ne(setup.players[1].starting_region, setup.players[2].starting_region)
	assert_eq(setup.resize_slots(0, 1), ERR_INVALID_PARAMETER)
	assert_eq(setup.players.size(), 3, "非法人数不得修改现有草稿")


func test_validate_requires_complete_unique_professions_and_starting_regions() -> void:
	var setup := SessionSetup.new()
	assert_eq(setup.validate(), PackedStringArray(["P1还未选择职业", "P1还未选择出生点"]))
	setup.players[0].profession_type = PlayerClass.PlayerCharacter.美食博主
	setup.players[0].starting_region = MapSection.REGION.十堰
	assert_true(setup.validate().is_empty())

	setup.resize_slots(2, 0)
	setup.players[1].profession_type = PlayerClass.PlayerCharacter.美食博主
	setup.players[1].starting_region = MapSection.REGION.十堰
	var errors := setup.validate()
	assert_has(errors, "P2职业已被P1选择")
	assert_has(errors, "P2出生点已被P1选择")


func test_validate_allows_duplicate_display_names() -> void:
	var setup := _valid_human_and_bot_setup()
	setup.players[0].display_name = "同名"
	setup.players[1].display_name = "同名"
	assert_true(setup.validate().is_empty())


func test_snapshot_and_legacy_mapping_are_independent_from_the_draft() -> void:
	var setup := _valid_setup()
	setup.target_score = 30
	setup.players[0].display_name = "  "
	var snapshot := setup.duplicate_snapshot()
	var legacy := snapshot.to_legacy_player_data()
	setup.players[0].display_name = "后来修改"
	setup.players[0].profession_type = PlayerClass.PlayerCharacter.商业博主

	assert_eq(snapshot.players[0].display_name, "  ")
	assert_eq(snapshot.target_score, 30)
	assert_eq(legacy[0], {
		"name": "P1",
		"location": "十堰",
		"job": "美食博主",
		"is_bot": false,
	})


func test_game_manager_commits_deep_snapshot_and_keeps_legacy_compatibility() -> void:
	var setup := _valid_setup()
	setup.players[0].display_name = "阿楚"
	setup.target_score = 25
	assert_eq(GameManager.prepare_local_session(setup), OK)
	assert_eq(GameManager.player_data, [{
		"name": "阿楚",
		"location": "十堰",
		"job": "美食博主",
		"is_bot": false,
	}])

	setup.players[0].display_name = "污染快照"
	var active := GameManager.get_active_session_setup()
	assert_eq(GameManager.get_target_score(), 25)
	assert_eq(active.players[0].display_name, "阿楚")
	active.players[0].display_name = "污染返回值"
	assert_eq(GameManager.get_active_session_setup().players[0].display_name, "阿楚")


func test_target_score_accepts_only_the_four_formal_options() -> void:
	var setup := _valid_setup()
	for target: int in SessionSetup.TARGET_SCORE_OPTIONS:
		setup.target_score = target
		assert_true(setup.validate().is_empty(), "%d分应为合法目标" % target)
	setup.target_score = 19
	assert_has(setup.validate(), "目标分数须为15、20、25或30分")


func test_prepare_is_idempotent_for_same_setup_and_rejects_a_different_one() -> void:
	var setup := _valid_setup()
	assert_eq(GameManager.prepare_local_session(setup), OK)
	assert_eq(GameManager.prepare_local_session(setup.duplicate_snapshot()), OK)
	var different := setup.duplicate_snapshot()
	different.players[0].display_name = "另一局"
	assert_eq(GameManager.prepare_local_session(different), ERR_ALREADY_EXISTS)
	assert_eq(GameManager.get_active_session_setup().players[0].display_name, "P1")


func test_invalid_or_non_local_setup_is_not_committed() -> void:
	var incomplete := SessionSetup.new()
	assert_eq(GameManager.prepare_local_session(incomplete), ERR_INVALID_DATA)
	incomplete.mode = SessionSetup.GameMode.NETWORK
	assert_eq(GameManager.prepare_local_session(incomplete), ERR_INVALID_PARAMETER)
	assert_null(GameManager.get_active_session_setup())
	assert_true(GameManager.player_data.is_empty())


func test_main_map_applies_typed_setup_without_a_string_round_trip() -> void:
	var setup := _valid_human_and_bot_setup()
	assert_eq(GameManager.prepare_local_session(setup), OK)
	var committed := GameManager.get_active_session_setup()
	var bot_config: PlayerSetup = committed.players[1]
	var map_controller: Node2D = MAIN_MAP_SCRIPT.new() as Node2D
	var player := PlayerClass.new()
	autofree(map_controller)
	autofree(player)

	map_controller.call(&"_apply_typed_player_setup", player, bot_config)
	assert_eq(player.player_name, "电脑测试")
	assert_eq(player.player_types, PlayerClass.PlayerCharacter.探险博主)
	assert_eq(player.start_coord, MapSection.出生点坐标[MapSection.REGION.恩施])
	assert_eq(player.player_index, 1)
	assert_true(player.is_bot)


func test_main_map_legacy_setup_preserves_optional_bot_identity() -> void:
	var map_controller: Node2D = MAIN_MAP_SCRIPT.new() as Node2D
	var player := PlayerClass.new()
	autofree(map_controller)
	autofree(player)
	map_controller.call(&"_apply_legacy_player_setup", player, {
		"name": "旧入口电脑",
		"job": "探险博主",
		"location": "恩施",
		"is_bot": true,
	}, 3)
	assert_eq(player.player_name, "旧入口电脑")
	assert_eq(player.player_types, PlayerClass.PlayerCharacter.探险博主)
	assert_eq(player.start_coord, MapSection.出生点坐标[MapSection.REGION.恩施])
	assert_eq(player.player_index, 3)
	assert_true(player.is_bot)


func test_reset_then_prepare_a_second_typed_session_has_no_first_session_state() -> void:
	var first := _valid_setup()
	first.players[0].display_name = "第一局"
	assert_eq(GameManager.prepare_local_session(first), OK)
	var first_snapshot := GameManager.get_active_session_setup()
	assert_eq(first_snapshot.players[0].display_name, "第一局")

	GameManager.reset_session(false)
	assert_null(GameManager.get_active_session_setup())
	assert_true(GameManager.player_data.is_empty())

	var second := _valid_human_and_bot_setup()
	second.players[0].display_name = "第二局玩家"
	assert_eq(GameManager.prepare_local_session(second), OK)
	var second_snapshot := GameManager.get_active_session_setup()
	assert_eq(second_snapshot.players.size(), 2)
	assert_eq(second_snapshot.players[0].display_name, "第二局玩家")
	assert_eq(second_snapshot.players[1].display_name, "电脑测试")
	assert_true(second_snapshot.players[1].is_bot())
	assert_eq(GameManager.player_data.size(), 2)
	assert_eq(GameManager.player_data[0]["name"], "第二局玩家")
	assert_eq(GameManager.player_data[1]["name"], "电脑测试")
	assert_false(str(GameManager.player_data).contains("第一局"))
	assert_eq(first_snapshot.players[0].display_name, "第一局", "旧快照不得被新局污染")


func _valid_setup() -> SessionSetup:
	var setup := SessionSetup.new()
	setup.players[0].profession_type = PlayerClass.PlayerCharacter.美食博主
	setup.players[0].starting_region = MapSection.REGION.十堰
	return setup


func _valid_human_and_bot_setup() -> SessionSetup:
	var setup := SessionSetup.new()
	assert_eq(setup.resize_slots(1, 1), OK)
	var human: PlayerSetup = setup.players[0]
	var bot: PlayerSetup = setup.players[1]
	human.display_name = "真人测试"
	human.profession_type = PlayerClass.PlayerCharacter.美食博主
	human.starting_region = MapSection.REGION.十堰
	bot.display_name = "电脑测试"
	bot.profession_type = PlayerClass.PlayerCharacter.探险博主
	bot.starting_region = MapSection.REGION.恩施
	assert_true(setup.validate().is_empty())
	return setup
