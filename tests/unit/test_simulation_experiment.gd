extends GutTest

const BALANCE_RUNNER_SCRIPT := preload("res://tools/balance_simulation_runner.gd")

var _saved_seed: int
var _saved_profile: GameManager.RuntimeProfile
var _saved_players: Array[PlayerClass] = []

func before_each() -> void:
	_saved_seed = GameManager.get_session_seed()
	_saved_profile = GameManager.runtime_profile
	_saved_players.assign(TurnManager.players)

func after_each() -> void:
	GameManager.configure_session(_saved_seed, _saved_profile)
	TurnManager.players.assign(_saved_players)

func test_standard_schedule_contains_972_matches() -> void:
	var schedule := SimulationSchedule.build_standard(20260824, 108)
	assert_eq(schedule.size(), 972)

func test_each_36_match_cycle_is_orthogonal_for_every_seat() -> void:
	for player_count: int in [2, 3, 6]:
		for repeat_index: int in 3:
			var pairs_by_seat: Array[Dictionary] = []
			for _seat: int in player_count:
				pairs_by_seat.append({})
			for local_index: int in 36:
				var config := SimulationSchedule.build_match(
					player_count,
					SimulationDecisionProvider.Strategy.LEGAL_RANDOM,
					repeat_index * 36 + local_index
				)
				assert_eq(config.locations.size(), player_count)
				assert_eq(config.professions.size(), player_count)
				assert_eq(_unique_count(config.locations), player_count, "同局地区不得重复")
				assert_eq(_unique_count(config.professions), player_count, "同局职业不得重复")
				for seat: int in player_count:
					pairs_by_seat[seat]["%s|%s" % [config.locations[seat], config.professions[seat]]] = true
			for seat: int in player_count:
				assert_eq(pairs_by_seat[seat].size(), 36, "每个座位每轮必须覆盖全部地区×职业组合")

func test_world_seed_is_paired_across_strategies_but_decision_seed_is_not() -> void:
	var random_config := SimulationSchedule.build_match(3, SimulationDecisionProvider.Strategy.LEGAL_RANDOM, 17, 1234)
	var survival_config := SimulationSchedule.build_match(3, SimulationDecisionProvider.Strategy.SURVIVAL_GREEDY, 17, 1234)
	var score_config := SimulationSchedule.build_match(3, SimulationDecisionProvider.Strategy.SCORE_GREEDY, 17, 1234)
	assert_eq(random_config.world_seed, survival_config.world_seed)
	assert_eq(random_config.world_seed, score_config.world_seed)
	assert_ne(random_config.decision_seed, survival_config.decision_seed)
	assert_ne(survival_config.decision_seed, score_config.decision_seed)
	assert_eq(SimulationDecisionProvider.parse_strategy("balanced_greedy"), SimulationDecisionProvider.Strategy.SURVIVAL_GREEDY)

func test_decision_rng_does_not_advance_world_rng() -> void:
	GameManager.configure_session(445566, GameManager.RuntimeProfile.HEADLESS_SIMULATION)
	var provider := SimulationDecisionProvider.new(SimulationDecisionProvider.Strategy.LEGAL_RANDOM, 998877)
	for _index: int in 30:
		provider.pick_value([1, 2, 3, 4, 5])
	var after_decisions: int = GameManager.randi_between(0, 1_000_000)
	GameManager.configure_session(445566, GameManager.RuntimeProfile.HEADLESS_SIMULATION)
	var without_decisions: int = GameManager.randi_between(0, 1_000_000)
	assert_eq(after_decisions, without_decisions)

func test_match_config_round_trips_for_replay() -> void:
	var original := SimulationSchedule.build_match(6, SimulationDecisionProvider.Strategy.SCORE_GREEDY, 91, 777)
	original.target_score = 25
	var restored := SimulationMatchConfig.from_dictionary(original.to_dictionary())
	assert_eq(restored.to_dictionary(), original.to_dictionary())
	assert_eq(restored.target_score, 25)

func test_match_config_normalizes_invalid_target_score_to_formal_default() -> void:
	var config := SimulationSchedule.build_match(2, SimulationDecisionProvider.Strategy.LEGAL_RANDOM, 0, 777)
	config.target_score = 19
	assert_eq(config.target_score, SessionSetup.DEFAULT_TARGET_SCORE)

	var restored := SimulationMatchConfig.from_dictionary({"target_score": 999})
	assert_eq(restored.target_score, SessionSetup.DEFAULT_TARGET_SCORE)
	assert_eq(int(restored.to_dictionary().target_score), SessionSetup.DEFAULT_TARGET_SCORE)

func test_single_player_cannot_close_out_by_elimination_in_simulation() -> void:
	var runner: Node = BALANCE_RUNNER_SCRIPT.new()
	var player := PlayerClass.new()
	TurnManager.players.assign([player])
	assert_false(bool(runner.call(&"_can_close_out_by_elimination", player)))
	TurnManager.players.clear()
	player.free()
	runner.free()

func test_telemetry_records_zero_champion_credit_when_result_has_no_winner() -> void:
	var config := SimulationSchedule.build_match(2, SimulationDecisionProvider.Strategy.LEGAL_RANDOM, 0, 777)
	var recorder := BalanceTelemetryRecorder.new()
	recorder.start_match(config, [])
	var result := GameResult.new(GameResult.EndReason.SOLO_DEFEAT, 1, [])
	var report := recorder.finish_match(result)
	assert_eq(report.get("winners", []), [])
	assert_eq(float(report.get("champion_credit", -1.0)), 0.0)

func test_observation_exposes_own_cards_but_only_public_opponent_counts() -> void:
	var original_players: Array[PlayerClass] = TurnManager.players.duplicate()
	var self_player := PlayerClass.new()
	var opponent := PlayerClass.new()
	self_player.player_index = 0
	opponent.player_index = 1
	var own_food := 食物牌.new()
	own_food.food_id = &"own_food"
	var hidden_food := 食物牌.new()
	hidden_food.food_id = &"hidden_food"
	self_player.食物牌手牌.append(own_food)
	opponent.食物牌手牌.append(hidden_food)
	TurnManager.players.assign([self_player, opponent])
	var observation := SimulationObservation.capture(self_player)
	assert_has(observation.own_food_ids, &"own_food")
	assert_does_not_have(observation.own_food_ids, &"hidden_food")
	assert_eq(observation.public_players[1].food_count, 1)
	assert_false(observation.public_players[1].has("food_ids"))
	TurnManager.players.assign(original_players)
	self_player.free()
	opponent.free()

func _unique_count(values: Array) -> int:
	var unique := {}
	for value in values:
		unique[value] = true
	return unique.size()
