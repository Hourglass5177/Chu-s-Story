extends GutTest

func before_each() -> void:
	GameManager.reset_session(false)

func after_each() -> void:
	GameManager.reset_session(false)

func test_tutorial_setup_is_fixed_and_valid() -> void:
	var setup := TutorialDefinition.make_setup()
	assert_eq(setup.mode, SessionSetup.GameMode.TUTORIAL)
	assert_eq(setup.players.size(), 1)
	assert_eq(setup.players[0].profession_type, PlayerClass.PlayerCharacter.生活博主)
	assert_eq(setup.bot_count, 0)
	assert_true(setup.validate().is_empty())
	assert_eq(setup.target_score, 20)

func test_local_entry_cannot_accept_tutorial_setup() -> void:
	assert_eq(GameManager.begin_local_session(TutorialDefinition.make_setup()), ERR_INVALID_PARAMETER)
	assert_false(GameManager.is_tutorial_session())

func test_tutorial_snapshot_is_independent_and_reset_clears_scope() -> void:
	assert_eq(GameManager.begin_tutorial_session(), OK)
	var snapshot := GameManager.get_active_session_setup()
	snapshot.mode = SessionSetup.GameMode.LOCAL
	snapshot.players[0].profession_type = PlayerClass.PlayerCharacter.魔术博主
	assert_true(GameManager.is_tutorial_session())
	assert_eq(GameManager.get_active_session_setup().players[0].profession_type, PlayerClass.PlayerCharacter.生活博主)
	assert_false(GameManager.allows_tutorial_action(&"collect"), "No live controller means no teaching actions")
	GameManager.reset_session()
	assert_false(GameManager.is_tutorial_session())
	assert_true(GameManager.allows_tutorial_action(&"collect"))

func test_tutorial_discovery_is_unchanged_in_memory() -> void:
	GameManager.begin_tutorial_session()
	var before := DiscoveryManager._discovered.duplicate(true)
	assert_false(DiscoveryManager.record_food_face_presented(TutorialDefinition.FOOD))
	assert_false(DiscoveryManager.record_discovery(DiscoveryManager.KIND_MINIGAME, &"tianmen_tang_su"))
	assert_eq(DiscoveryManager._discovered, before)

func test_tutorial_action_deadline_stays_off_after_nested_modal() -> void:
	GameManager.begin_tutorial_session()
	TurnManager.GameOn = true
	TurnManager.now_phase = TurnManager.TurnPhase.ACTION
	TurnManager._start_phase_timer(15.0)
	assert_true(TurnManager.turn_timer.is_stopped())
	var first := TurnManager.acquire_modal(&"tutorial_test", TurnManager.ModalResumePolicy.RESET_ACTION)
	var second := TurnManager.acquire_modal(&"nested", TurnManager.ModalResumePolicy.RESUME_REMAINING)
	assert_true(TurnManager.release_modal(second))
	assert_true(TurnManager.release_modal(first))
	assert_true(TurnManager.turn_timer.is_stopped())
	assert_eq(TurnManager.modal_resolution_depth, 0)

func test_tutorial_animation_timer_still_works_and_local_deadline_unchanged() -> void:
	GameManager.begin_tutorial_session()
	TurnManager.now_phase = TurnManager.TurnPhase.ROLL_DICE
	TurnManager._start_phase_timer(3.0)
	assert_false(TurnManager.turn_timer.is_stopped())
	GameManager.reset_session()
	TurnManager.now_phase = TurnManager.TurnPhase.ACTION
	TurnManager._start_phase_timer(15.0)
	assert_false(TurnManager.turn_timer.is_stopped())
	assert_almost_eq(TurnManager.turn_timer.time_left, 15.0, 0.1)

func test_lesson_copy_stays_short_and_uses_existing_content() -> void:
	assert_eq(TutorialDefinition.PROMPTS.size(), TutorialDefinition.TITLES.size())
	for line: String in TutorialDefinition.PROMPTS:
		assert_lte(line.length(), 26)
	assert_eq(TutorialDefinition.CARD.inheritance_task_id, &"tianmen_tang_su")
	assert_eq(TutorialDefinition.FOOD.food_id, &"yun_meng_yu_mian")
	assert_true(ResourceLoader.exists(TutorialController.SCREENSHOT_PATH))

func test_exit_cancels_real_demonstration_and_late_confirmation_cannot_unlock() -> void:
	GameManager.begin_tutorial_session()
	var subject := PlayerClass.new()
	subject.player_index = 0
	subject.current_energy = 6
	subject.alive = true
	subject.onTurn = true
	subject.非遗牌手牌.append(TutorialDefinition.CARD)
	TurnManager.players.assign([subject])
	TurnManager.now_player_index = 0
	TurnManager.now_phase = TurnManager.TurnPhase.ACTION
	TurnManager.GameOn = true
	var participants: Array[PlayerClass] = [subject]
	HeritageTaskManager.reset_for_new_game(participants)
	var pending := HeritageTaskManager.begin_attempt(subject, TutorialDefinition.CARD)
	assert_not_null(pending)
	assert_eq(subject.current_energy, 5)
	var controller := TutorialController.new()
	controller.player = subject
	controller.step = 4
	controller._generation = TurnManager.get_session_generation()
	controller._active = true
	controller._attempt = pending
	GameManager.tutorial_controller = controller
	GameManager.reset_session(false)
	controller._on_primary()
	assert_false(HeritageTaskManager.is_inherited(TutorialDefinition.CARD))
	assert_false(controller.is_current())
	assert_true(InteractionCoordinator.get_active_snapshot().is_empty())
	assert_eq(TurnManager.modal_resolution_depth, 0)
	controller.free()
	subject.free()
