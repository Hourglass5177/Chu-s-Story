extends GutTest

var _saved_seed: int
var _saved_profile: GameManager.RuntimeProfile

func before_each() -> void:
	_saved_seed = GameManager.get_session_seed()
	_saved_profile = GameManager.runtime_profile

func after_each() -> void:
	GameManager.configure_session(_saved_seed, _saved_profile)

func test_all_implemented_events_have_a_presentation_tier() -> void:
	assert_eq(EventPresentationDirector.PRESENTATION_TIERS.size(), 40)
	for event_id: StringName in EventManager.IMPLEMENTED_EVENT_IDS:
		assert_true(EventPresentationDirector.PRESENTATION_TIERS.has(event_id), str(event_id))

func test_mei_mei_yu_gong_is_sequential_and_uses_a_single_d6() -> void:
	var director := EventPresentationDirector.new()
	assert_eq(director.get_tier(&"mei_mei_yu_gong"), EventPresentationDirector.Tier.SEQUENTIAL)
	director.free()
	GameManager.configure_session(551122, GameManager.RuntimeProfile.HEADLESS_SIMULATION)
	for _index: int in 100:
		var value := EventManager._roll_d6()
		assert_between(value, 1, 6)
