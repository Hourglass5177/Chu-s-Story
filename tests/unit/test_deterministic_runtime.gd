extends GutTest

var _saved_seed: int
var _saved_profile: GameManager.RuntimeProfile

func before_each() -> void:
	_saved_seed = GameManager.get_session_seed()
	_saved_profile = GameManager.runtime_profile

func after_each() -> void:
	GameManager.configure_session(_saved_seed, _saved_profile)

func test_same_seed_replays_random_sequence_and_shuffle() -> void:
	GameManager.configure_session(24081999, GameManager.RuntimeProfile.HEADLESS_SIMULATION)
	var first_rolls: Array[int] = []
	for _index: int in 12:
		first_rolls.append(GameManager.randi_between(1, 6) + GameManager.randi_between(1, 6))
	var first_cards := [1, 2, 3, 4, 5, 6]
	GameManager.shuffle_array(first_cards)

	GameManager.configure_session(24081999, GameManager.RuntimeProfile.HEADLESS_SIMULATION)
	var replay_rolls: Array[int] = []
	for _index: int in 12:
		replay_rolls.append(GameManager.randi_between(1, 6) + GameManager.randi_between(1, 6))
	var replay_cards := [1, 2, 3, 4, 5, 6]
	GameManager.shuffle_array(replay_cards)

	assert_eq(replay_rolls, first_rolls)
	assert_eq(replay_cards, first_cards)

func test_runtime_profile_changes_presentation_only_not_random_stream() -> void:
	GameManager.configure_session(778899, GameManager.RuntimeProfile.NORMAL)
	var normal_values: Array[int] = []
	for _index: int in 20:
		normal_values.append(GameManager.randi_between(0, 100000))
	GameManager.configure_session(778899, GameManager.RuntimeProfile.HEADLESS_SIMULATION)
	var simulated_values: Array[int] = []
	for _index: int in 20:
		simulated_values.append(GameManager.randi_between(0, 100000))
	assert_eq(simulated_values, normal_values)

func test_two_dice_stay_within_the_existing_distribution_bounds() -> void:
	GameManager.configure_session(123456, GameManager.RuntimeProfile.HEADLESS_SIMULATION)
	var counts: Dictionary[int, int] = {}
	for _index: int in 3600:
		var value := GameManager.randi_between(1, 6) + GameManager.randi_between(1, 6)
		counts[value] = counts.get(value, 0) + 1
	assert_eq(counts.keys().min(), 2)
	assert_eq(counts.keys().max(), 12)
	assert_gt(counts[7], counts[2])
	assert_gt(counts[7], counts[12])

func test_same_seed_rebuilds_the_same_complete_deck_order() -> void:
	GameManager.configure_session(424242, GameManager.RuntimeProfile.HEADLESS_SIMULATION)
	ResourceManager.reset_for_new_game()
	var first_food := ResourceManager.食物牌库.map(func(card): return String(card.food_id))
	var first_events := ResourceManager.事件牌库.map(func(card): return String(card.event_id))
	var first_feiyi := ResourceManager.非遗牌库.map(func(card): return card.card_name)

	GameManager.configure_session(424242, GameManager.RuntimeProfile.HEADLESS_SIMULATION)
	ResourceManager.reset_for_new_game()
	assert_eq(ResourceManager.食物牌库.map(func(card): return String(card.food_id)), first_food)
	assert_eq(ResourceManager.事件牌库.map(func(card): return String(card.event_id)), first_events)
	assert_eq(ResourceManager.非遗牌库.map(func(card): return card.card_name), first_feiyi)
