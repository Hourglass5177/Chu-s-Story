extends GutTest

const EVENT_DIR := "res://Cards/事件牌"
## 固定让【艺径寻踪】的首次 2D6 至少为 3，专门覆盖“终点为非遗点时免费学习”分支。
const YI_JING_XUN_ZONG_CONTRACT_SEED := 4133

var _food_deck_backup: Array[卡牌基类]
var _event_deck_backup: Array[事件牌]
var _event_discard_backup: Array[事件牌]
var _regional_decks_backup: Dictionary
var _market_backup: Array[非遗牌]
var _players: Array[PlayerClass] = []
var _map: MAP = null
var _game_seed_backup: int
var _runtime_profile_backup: GameManager.RuntimeProfile
var _target_score_backup: int

func before_each() -> void:
	_game_seed_backup = GameManager.get_session_seed()
	_runtime_profile_backup = GameManager.runtime_profile
	_target_score_backup = GameManager.get_target_score()
	_food_deck_backup.assign(ResourceManager.食物牌库)
	_event_deck_backup.assign(ResourceManager.事件牌库)
	_event_discard_backup.assign(ResourceManager.事件弃牌堆)
	_regional_decks_backup = ResourceManager.地区非遗牌库.duplicate(true)
	_market_backup = MarketManager.get_inventory()
	ProfessionManager.reset_for_new_game()

func after_each() -> void:
	_teardown_scenario()
	ResourceManager.食物牌库.assign(_food_deck_backup)
	ResourceManager.事件牌库.assign(_event_deck_backup)
	ResourceManager.事件弃牌堆.assign(_event_discard_backup)
	ResourceManager.地区非遗牌库 = _regional_decks_backup.duplicate(true)
	MarketManager.reset_for_new_game()
	for card: 非遗牌 in _market_backup:
		MarketManager.deposit_card(card, &"test_restore")
	ProfessionManager.reset_for_new_game()
	GameManager.configure_session(_game_seed_backup, _runtime_profile_backup, _target_score_backup)

func test_every_available_event_completes_a_deterministic_resolution() -> void:
	var cards: Array[事件牌] = []
	for file_name: String in DirAccess.get_files_at(EVENT_DIR):
		if not file_name.ends_with(".tres"):
			continue
		var card := load(EVENT_DIR + "/" + file_name) as 事件牌
		if card.is_available():
			cards.append(card)
	cards.sort_custom(func(first: 事件牌, second: 事件牌) -> bool: return first.event_id < second.event_id)
	assert_eq(cards.size(), 40)

	for index in cards.size():
		var card: 事件牌 = cards[index]
		_setup_scenario(card.event_id)
		var event_seed := YI_JING_XUN_ZONG_CONTRACT_SEED if card.event_id == &"yi_jing_xun_zong" else 4100 + index
		GameManager.configure_session(event_seed, GameManager.RuntimeProfile.HEADLESS_SIMULATION)
		await EventManager.resolve_event(_players[0], card)

		assert_false(EventManager.resolving, card.card_name + " 结算后必须退出事件模态")
		assert_eq(TurnManager.modal_resolution_depth, 0, card.card_name + " 不得遗留模态深度")
		if card.retainable:
			assert_true(_players[0].事件牌手牌.has(card), card.card_name + " 应进入触发者的保留牌区")
			assert_false(ResourceManager.事件弃牌堆.has(card), card.card_name + " 尚未使用时不能弃置")
		else:
			assert_true(ResourceManager.事件弃牌堆.has(card), card.card_name + " 结算后应进入弃牌区")
			assert_false(_players[0].事件牌手牌.has(card), card.card_name + " 不是保留牌")
		assert_true(_event_specific_contract_holds(card.event_id), card.card_name + " 的确定性效果契约未满足")
		_teardown_scenario()

func test_zuo_shou_yu_li_uses_lifestyle_bloggers_zero_work_cost() -> void:
	_setup_scenario(&"zuo_shou_yu_li")
	_players[0].player_types = PlayerClass.PlayerCharacter.生活博主
	_players[0].current_energy = 0
	var card := load("res://Cards/事件牌/坐收渔利.tres") as 事件牌
	await EventManager.resolve_event(_players[0], card)
	assert_eq(_players[0].current_energy, 0)
	assert_eq(_players[0].current_money, 1375)

func test_explicit_scenery_events_trigger_travel_blogger_bonus() -> void:
	_setup_scenario(&"chen_jin_ti_yan")
	_players[0].player_types = PlayerClass.PlayerCharacter.旅行博主
	var immersion := load("res://Cards/事件牌/沉浸体验.tres") as 事件牌
	await EventManager.resolve_event(_players[0], immersion)
	assert_eq(_players[0].current_money, 1250)

	_setup_scenario(&"you_mu_cheng_huai")
	_players[0].player_types = PlayerClass.PlayerCharacter.旅行博主
	var roam := load("res://Cards/事件牌/游目骋怀.tres") as 事件牌
	await EventManager.resolve_event(_players[0], roam)
	assert_true(_players[0].事件牌手牌.has(roam))
	await EventManager.request_play_retained_event(_players[0], roam)
	assert_eq(_players[0].current_money, 1250)

func _setup_scenario(event_id: StringName) -> void:
	_teardown_scenario()
	EventManager.reset_for_new_game()
	ProfessionManager.reset_for_new_game()
	MarketManager.reset_for_new_game()
	EventManager.bind_runtime(null, null)
	EventManager.choice_strategy = func(request: EventChoiceRequest):
		if request.options.is_empty():
			return null
		if request.multiple:
			return request.options.slice(0, request.max_selections)
		if request.kind == EventChoiceRequest.ChoiceKind.格子:
			if event_id == &"yi_jing_xun_zong":
				for option in request.options:
					if option is MapSection and option.type == MapSection.SectionType.非遗:
						return option
			return request.options.back()
		return request.options[0]

	_map = MAP.new()
	for coordinate in range(-6, 7):
		var section := MapSection.new()
		section.location_index = Vector3i(coordinate, -coordinate, 0)
		section.logical_index = coordinate + 6
		section.section_name = "测试格%d" % coordinate
		section.position = Vector2(coordinate * 80.0, 0.0)
		section.region = MapSection.REGION.鄂州
		if coordinate in [1, 4]:
			section.type = MapSection.SectionType.打工
		elif coordinate in [-2, 2]:
			section.type = MapSection.SectionType.风景
		elif coordinate == 3:
			section.type = MapSection.SectionType.非遗
		elif coordinate == 0:
			section.type = MapSection.SectionType.事件
		_map.add_child(section)
		_map.grid_map[section.location_index] = section

	_players.assign([
		_make_player("甲", 0, PlayerClass.PlayerCharacter.美食博主),
		_make_player("乙", 5, PlayerClass.PlayerCharacter.商业博主),
		_make_player("丙", -5, PlayerClass.PlayerCharacter.旅行博主),
	])
	for player: PlayerClass in _players:
		player.map = _map
		_map.grid_map[player.now_pos].is_occupied = true

	_players[0].last_successful_feiyi_section = _map.grid_map[Vector3i(3, -3, 0)]
	_players[0].非遗牌手牌.append(_make_feiyi("甲技艺", 非遗牌.CardCategory.手工技艺, 2))
	_players[0].非遗牌手牌.append(_make_feiyi("甲音乐", 非遗牌.CardCategory.民间音乐, 1))
	_players[0].非遗牌手牌.append(_make_feiyi("甲国宝", 非遗牌.CardCategory.国家级非遗, 3))
	_players[1].非遗牌手牌.append(_make_feiyi("乙技艺", 非遗牌.CardCategory.手工技艺, 1))
	_players[1].非遗牌手牌.append(_make_feiyi("乙音乐", 非遗牌.CardCategory.民间音乐, 2))
	_players[2].非遗牌手牌.append(_make_feiyi("丙技艺", 非遗牌.CardCategory.手工技艺, 1))
	for player: PlayerClass in _players:
		player.食物牌手牌.append(_make_food(player.player_name + "食物A"))
		player.食物牌手牌.append(_make_food(player.player_name + "食物B"))

	ResourceManager.食物牌库.clear()
	for food_index in 12:
		ResourceManager.食物牌库.append(_make_food("牌库食物%d" % food_index))
	ResourceManager.事件弃牌堆.clear()
	ResourceManager.地区非遗牌库.clear()
	ResourceManager.地区非遗牌库[MapSection.REGION.鄂州] = [
		_make_feiyi("测试抽取非遗", 非遗牌.CardCategory.手工技艺, 1),
	]
	MarketManager.deposit_card(_make_feiyi("研究所藏品A", 非遗牌.CardCategory.手工技艺, 1), &"test")
	MarketManager.deposit_card(_make_feiyi("研究所藏品B", 非遗牌.CardCategory.民间音乐, 1), &"test")
	MarketManager.deposit_card(_make_feiyi("研究所藏品C", 非遗牌.CardCategory.神话传说, 1), &"test")

	if event_id == &"pou_duo_yi_gua":
		_players[0].current_money = 1500
		_players[1].current_money = 1000
		_players[2].current_money = 500
	elif event_id in [&"mei_mei_yu_gong", &"jing_pi_li_jin"]:
		for player: PlayerClass in _players:
			player.current_energy = 6

	TurnManager.players.assign(_players)
	TurnManager.player_num = _players.size()
	TurnManager.now_player_index = 0
	TurnManager.next_player_index = 1
	TurnManager.now_turn = 1
	TurnManager.now_phase = TurnManager.TurnPhase.ACTION
	TurnManager.modal_resolution_depth = 0
	TurnManager.map = _map
	TurnManager.GameOn = true

func _teardown_scenario() -> void:
	TurnManager.turn_timer.stop()
	TurnManager.GameOn = false
	TurnManager.modal_resolution_depth = 0
	TurnManager.players.clear()
	TurnManager.map = null
	EventManager.reset_for_new_game()
	ProfessionManager.reset_for_new_game()
	for player: PlayerClass in _players:
		if is_instance_valid(player):
			player.free()
	_players.clear()
	if is_instance_valid(_map):
		_map.free()
	_map = null

func _make_player(display_name: String, coordinate: int, character: PlayerClass.PlayerCharacter) -> PlayerClass:
	var player := PlayerClass.new()
	player.player_name = display_name
	player.player_types = character
	player.now_pos = Vector3i(coordinate, -coordinate, 0)
	player.current_energy = 6
	player.current_money = 1000
	player.sprite_frames = SpriteFrames.new()
	for key: PlayerClass.PlayerCharacter in PlayerClass.PlayerCharacter.values():
		var animation_name := StringName(PlayerClass.PlayerCharacter.find_key(key))
		if not player.sprite_frames.has_animation(animation_name):
			player.sprite_frames.add_animation(animation_name)
		player.立绘精一图组[key] = null
		player.立绘精二图组[key] = null
	return player

func _make_feiyi(display_name: String, category: 非遗牌.CardCategory, rarity: int) -> 非遗牌:
	var card := 非遗牌.new()
	card.card_name = display_name
	card.category = category
	card.rarity = rarity
	card.region = 非遗牌.REGION.鄂州
	return card

func _make_food(display_name: String) -> 食物牌:
	var card := 食物牌.new()
	card.card_name = display_name
	return card

func _event_specific_contract_holds(event_id: StringName) -> bool:
	match event_id:
		&"zuo_shou_yu_li":
			return _players[0].current_money == 1375 and _players[0].current_energy == 5 \
				and _players[1].current_money == 1125 and _players[1].current_energy == 5
		&"pou_duo_yi_gua":
			return _players.all(func(player: PlayerClass) -> bool: return player.current_money == 1000)
		&"gu_zhu_yi_zhi":
			return ProfessionManager.get_blocked_turns(_players[0]) == 4
		&"ba_geng_xie_ye":
			return EventManager.get_status_remaining(_players[0], &"work_banned") == 3
		&"yi_chuang_zeng_shou":
			return _players[0].current_energy == 8
		&"wen_hua_xin_feng":
			return _players[0].current_money == 1200
		&"jiao_huan_ren_sheng":
			return _players[0].player_types == PlayerClass.PlayerCharacter.商业博主
		&"mei_mei_yu_gong":
			return _players.all(func(player: PlayerClass) -> bool: return player.current_energy > 6)
		&"yang_jing_xu_rui":
			return _players[0].current_energy == 12 and EventManager.get_status_remaining(_players[0], &"skip_moving") == 2 and EventManager.get_status_remaining(_players[0], &"skip_action") == 2
		&"cun_bu_nan_xing":
			return EventManager.get_status_remaining(_players[0], &"skip_moving") == 2
		&"jing_pi_li_jin":
			return _players[0].current_energy == 3
		&"bi_men_xie_ke":
			return EventManager.get_status_remaining(_players[0], &"scenery_banned") == 3
		&"juan_yi_xiu_zheng":
			return _players[0].current_energy == 11 and _players[0].食物牌手牌.size() == 1 and TurnManager.now_phase == TurnManager.TurnPhase.END
		&"chen_jin_ti_yan":
			return _players[0].current_energy == 12 and EventManager.get_status_remaining(_players[0], &"skip_moving") == 2
		&"yi_wai_zhi_xi":
			return _players[0].食物牌手牌.size() == 4
		&"xin_huo_xiang_chuan":
			return _players[0].current_energy == 9 and _players[1].非遗牌手牌.size() == 3
		&"you_shi_tong_xiang":
			return _players.all(func(player: PlayerClass) -> bool: return player.食物牌手牌.size() == 3)
		&"chuan_yi_hu_jian":
			return _players[0].非遗牌手牌.size() == 4 and _players[1].非遗牌手牌.size() == 1
		&"yi_cang_hu_huan":
			return _players[0].current_energy == 7 and _players[1].current_energy == 7 \
				and _has_card_named(_players[0].非遗牌手牌, "乙技艺") \
				and _has_card_named(_players[1].非遗牌手牌, "甲技艺")
		&"tai_jiu_huan_xin", &"wen_hua_gong_xiang":
			return _players[0].非遗牌手牌.size() + _players[0].食物牌手牌.size() + _players[0].事件牌手牌.size() == 3
		&"tong_tai_jing_ji":
			return _players[0].current_money != 1000 or _players[1].current_money != 1000
		&"yi_shi_hui_you":
			return _players[0].食物牌手牌.size() == 2 and _players[1].食物牌手牌.size() == 2 \
				and _has_card_named(_players[0].食物牌手牌, "乙食物A") \
				and _has_card_named(_players[1].食物牌手牌, "甲食物A")
		&"gu_di_chong_you":
			return _players[0].now_pos == Vector3i(3, -3, 0)
		&"dou_zhuan_xing_yi", &"tong_xing_feng_cai":
			return _players[0].now_pos == Vector3i(5, -5, 0) and _players[1].now_pos == Vector3i(0, 0, 0)
		&"yi_jing_xun_zong":
			return _players[0].now_pos == Vector3i(3, -3, 0) and _players[0].current_energy == 3 and _players[0].非遗牌手牌.size() == 4
		&"guo_bao_hu_hang":
			return EventManager.get_status_remaining(_players[0], &"free_move_phases") == 2 and EventManager.get_status_remaining(_players[1], &"free_move_phases") == 0
		&"jin_ji_bi_xian":
			return EventManager.is_loss_immune(_players[0])
		&"bai_ge_zheng_liu":
			# 三轮总点数允许平局；平局按正式规则无奖惩，不能被测试误判为未结算。
			return _players.all(func(player: PlayerClass) -> bool: return absi(player.current_money - 1000) in [0, 200])
		&"ri_xing_qian_li":
			return _players[0].now_pos != Vector3i(0, 0, 0)
		&"miao_shou_hui_chun", &"you_mu_cheng_huai", &"chang_xing_wu_zu", &"jin_chan_tuo_qiao", &"yi_hua_jie_mu":
			return _players[0].事件牌手牌.size() == 1
		&"jian_wang_zhi_lai", &"shi_ji_tao_zhen":
			return _players[0].非遗牌手牌.size() == 4 and MarketManager.get_inventory().size() == 2
		&"zhan_yi_gong_yan":
			return _players[0].非遗牌手牌.size() == 2 and MarketManager.get_inventory().size() == 4
		&"fu_di_chou_xin":
			return _players[0].非遗牌手牌.size() == 1 and MarketManager.get_inventory().size() == 5
		_:
			return false

func _has_card_named(cards: Array, card_name: String) -> bool:
	for card in cards:
		if card.card_name == card_name:
			return true
	return false
