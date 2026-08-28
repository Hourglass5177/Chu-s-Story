extends Node
signal event_on_trigger(event_name: String)
signal energy_changed(player: PlayerClass, previous_energy: int, current_energy: int, reason: String)
signal money_changed(player: PlayerClass, previous_money: int, current_money: int, reason: String)
signal score_changed(player: PlayerClass, previous_score: int, current_score: int, breakdown: Dictionary)
signal work_completed(player: PlayerClass, work_turns: int, income: int)
signal food_purchased(player: PlayerClass, card: 食物牌, price: int)
signal feiyi_hand_changed(player: PlayerClass)
signal food_hand_changed(player: PlayerClass)
signal card_hand_visual_requested(kind: CardHandVisualKind, player: PlayerClass, card: 卡牌基类, other_player: PlayerClass, reveal_detail: bool)

enum CardHandVisualKind {
	获得,
	失去,
	转移,
}
# 全局牌库
var 非遗牌库: Array[卡牌基类] = []
var 食物牌库: Array[卡牌基类] = []
var 事件牌库: Array[事件牌] = []
var 事件弃牌堆: Array[事件牌] = []
var 地区非遗牌上限字典: Dictionary[MapSection.REGION, int] = {}
var 类别非遗牌上限字典: Dictionary[非遗牌.CardCategory, int] = {}
var hud:HUD
## 只用于确认会话生命周期没有重复执行昂贵的整副牌库重建。
var _deck_build_generation: int = 0

const FOLK_MUSIC_MONEY_GAIN: int = 500
const FESTIVAL_ENERGY_GAIN: int = 3
const FESTIVAL_MONEY_GAIN: int = 500

const STRING_TO_REGION = {
	"鄂州":MapSection.REGION.鄂州,
	"恩施":MapSection.REGION.恩施,
	"黄冈":MapSection.REGION.黄冈,
	"黄石":MapSection.REGION.黄石,
	"荆门":MapSection.REGION.荆门,
	"荆州":MapSection.REGION.荆州,
	"潜江":MapSection.REGION.潜江,
	"神农架":MapSection.REGION.神农架,
	"十堰":MapSection.REGION.十堰,
	"随州":MapSection.REGION.随州,
	"天门":MapSection.REGION.天门,
	"武汉":MapSection.REGION.武汉,
	"仙桃":MapSection.REGION.仙桃,
	"咸宁":MapSection.REGION.咸宁,
	"襄阳":MapSection.REGION.襄阳,
	"孝感":MapSection.REGION.孝感,
	"宜昌":MapSection.REGION.宜昌,
	"其他":MapSection.REGION.其他,
	"未知":MapSection.REGION.未知
}

func _ready() -> void:
	reset_for_new_game()
	#hud = get_tree().get_first_node_in_group("HUD")
	

var 地区非遗牌库: Dictionary[MapSection.REGION, Array] = {} 

func reset_for_new_game() -> void:
	非遗牌库.clear()
	食物牌库.clear()
	事件牌库.clear()
	事件弃牌堆.clear()
	地区非遗牌库.clear()
	地区非遗牌上限字典.clear()
	类别非遗牌上限字典.clear()
	_init_decks()

func unbind_runtime() -> void:
	hud = null

func _init_decks() -> void:
	_deck_build_generation += 1
	# 调用新的分地区加载函数
	_load_regional_feiyi_cards("res://Cards/非遗牌")
	
	# 其他普通牌库保持原样加载
	_load_cards_from_dir("res://Cards/食物牌", 食物牌库)
	_load_event_cards("res://Cards/事件牌")
	_count_feiyi_in_category()
	GameManager.shuffle_array(非遗牌库)
	GameManager.shuffle_array(食物牌库)
	GameManager.shuffle_array(事件牌库)
	事件弃牌堆.clear()

func _load_event_cards(path: String) -> void:
	事件牌库.clear()
	var loaded: Array = []
	_load_cards_from_dir(path, loaded)
	for card in loaded:
		if card is 事件牌 and card.is_available():
			事件牌库.append(card as 事件牌)

# 【新增】：专门读取地区子文件夹的逻辑
func _load_regional_feiyi_cards(base_path: String) -> void:
	var dir = DirAccess.open(base_path)
	if dir:
		# 获取非遗牌目录下的所有子文件夹名称（比如 "鄂州", "恩施"）
		var region_folders = dir.get_directories() 
		
		for folder_name in region_folders:
			var region_path = base_path + "/" + folder_name
			var cards_array: Array[卡牌基类] = []
			
			# 复用你之前的通用读取函数，把这个地区的文件全读出来
			_load_cards_from_dir(region_path, cards_array)
			
			if cards_array.size() > 0:
				GameManager.shuffle_array(cards_array) # 仅对该地区洗牌
				非遗牌库.append_array(cards_array)
				地区非遗牌库[STRING_TO_REGION[folder_name]] = cards_array # 存入字典
				地区非遗牌上限字典[STRING_TO_REGION[folder_name]] = cards_array.size()
				print("已加载地区 [", folder_name, "] 非遗牌库，共 ", cards_array.size(), " 张")
	else:
		push_warning("警告：找不到非遗牌根目录 -> ", base_path)
		
func _load_cards_from_dir(path: String, target_array: Array) -> void:
	# 尝试打开目标文件夹
	var dir = DirAccess.open(path)
	
	if dir:
		# 获取文件夹下的所有文件名
		var files = dir.get_files()
		
		for file_name in files:
			# 过滤文件：我们只需要 .tres 结尾的文件，或者导出后的 .tres.remap 文件
			if file_name.ends_with(".tres") or file_name.ends_with(".tres.remap"):
				
				# 【防坑神器】：处理打包导出后后缀名变成 .remap 的情况
				var actual_file = file_name.trim_suffix(".remap") 
				var full_path = path + "/" + actual_file
				
				# 加载资源
				var card_resource = ResourceLoader.load(full_path)
				
				# 确保加载进来的确实是你的卡牌基类，防止把别的乱七八糟的资源混进去
				if card_resource is 卡牌基类:
					target_array.append(card_resource)
	else:
		push_warning("警告：牌库加载失败，找不到文件夹路径 -> ", path)

func _count_feiyi_in_category() -> void:
	for card:非遗牌 in 非遗牌库:
		if 类别非遗牌上限字典.has(card.category):
			类别非遗牌上限字典[card.category] += 1
		else: 类别非遗牌上限字典[card.category] = 1

# 【新增】：提供给外部查询该地区是否还有牌的接口
func has_feiyi_in_region(region:MapSection.REGION) -> bool:
	if 地区非遗牌库.has(region):
		return 地区非遗牌库[region].size() > 0
	return false

func add_feiyi_card(player: PlayerClass, card: 非遗牌, refresh: bool = true, reveal_detail: bool = false) -> bool:
	if player == null or card == null or player.非遗牌手牌.has(card):
		return false
	player.非遗牌手牌.append(card)
	card_hand_visual_requested.emit(CardHandVisualKind.获得, player, card, null, reveal_detail)
	_emit_feiyi_hand_changed(player, refresh)
	return true

func remove_feiyi_card(player: PlayerClass, card: 非遗牌, refresh: bool = true) -> bool:
	if player == null or card == null or not player.非遗牌手牌.has(card):
		return false
	player.非遗牌手牌.erase(card)
	card_hand_visual_requested.emit(CardHandVisualKind.失去, player, card, null, false)
	_emit_feiyi_hand_changed(player, refresh)
	return true

func transfer_feiyi_card(source: PlayerClass, target: PlayerClass, card: 非遗牌) -> bool:
	if source == null or target == null or source == target or card == null:
		return false
	if not source.非遗牌手牌.has(card) or target.非遗牌手牌.has(card):
		return false
	source.非遗牌手牌.erase(card)
	target.非遗牌手牌.append(card)
	card_hand_visual_requested.emit(CardHandVisualKind.转移, source, card, target, false)
	_emit_feiyi_hand_changed(source, true)
	_emit_feiyi_hand_changed(target, true)
	return true

func swap_feiyi_cards(first: PlayerClass, first_card: 非遗牌, second: PlayerClass, second_card: 非遗牌) -> bool:
	if first == null or second == null or first == second or first_card == null or second_card == null:
		return false
	if not first.非遗牌手牌.has(first_card) or not second.非遗牌手牌.has(second_card):
		return false
	first.非遗牌手牌.erase(first_card)
	second.非遗牌手牌.erase(second_card)
	first.非遗牌手牌.append(second_card)
	second.非遗牌手牌.append(first_card)
	card_hand_visual_requested.emit(CardHandVisualKind.转移, first, first_card, second, false)
	card_hand_visual_requested.emit(CardHandVisualKind.转移, second, second_card, first, false)
	_emit_feiyi_hand_changed(first, true)
	_emit_feiyi_hand_changed(second, true)
	return true

func add_food_card(player: PlayerClass, card: 食物牌) -> bool:
	if player == null or card == null or player.食物牌手牌.has(card):
		return false
	player.食物牌手牌.append(card)
	card_hand_visual_requested.emit(CardHandVisualKind.获得, player, card, null, false)
	food_hand_changed.emit(player)
	return true

func remove_food_card(player: PlayerClass, card: 食物牌) -> bool:
	if player == null or card == null or not player.食物牌手牌.has(card):
		return false
	player.食物牌手牌.erase(card)
	card_hand_visual_requested.emit(CardHandVisualKind.失去, player, card, null, false)
	food_hand_changed.emit(player)
	return true

func add_event_card(player: PlayerClass, card: 事件牌) -> bool:
	if player == null or card == null or player.事件牌手牌.has(card):
		return false
	player.事件牌手牌.append(card)
	card_hand_visual_requested.emit(CardHandVisualKind.获得, player, card, null, false)
	return true

func remove_event_card(player: PlayerClass, card: 事件牌) -> bool:
	if player == null or card == null or not player.事件牌手牌.has(card):
		return false
	player.事件牌手牌.erase(card)
	card_hand_visual_requested.emit(CardHandVisualKind.失去, player, card, null, false)
	return true

func swap_food_hands(first: PlayerClass, second: PlayerClass) -> bool:
	if first == null or second == null or first == second:
		return false
	var first_cards: Array[食物牌] = []
	first_cards.assign(first.食物牌手牌)
	var second_cards: Array[食物牌] = []
	second_cards.assign(second.食物牌手牌)
	first.食物牌手牌.assign(second_cards)
	second.食物牌手牌.assign(first_cards)
	for card: 食物牌 in first_cards:
		card_hand_visual_requested.emit(CardHandVisualKind.转移, first, card, second, false)
	for card: 食物牌 in second_cards:
		card_hand_visual_requested.emit(CardHandVisualKind.转移, second, card, first, false)
	food_hand_changed.emit(first)
	food_hand_changed.emit(second)
	return not first_cards.is_empty() or not second_cards.is_empty()

func _emit_feiyi_hand_changed(player: PlayerClass, refresh: bool) -> void:
	feiyi_hand_changed.emit(player)
	if not refresh:
		return
	calculate_victory_score(player)
	if hud != null and TurnManager.GameOn \
			and TurnManager.now_player_index >= 0 \
			and TurnManager.now_player_index < TurnManager.players.size() \
			and TurnManager.players[TurnManager.now_player_index] == player:
		hud.refresh_feiyi_list(player)
		hud._update_player_stats(player)

# 2. 发牌中心
func draw_card(player: PlayerClass, deck_type: 卡牌基类.CardType, region: MapSection.REGION, collection_cost: int = 1, reveal_feiyi_detail: bool = false) -> 卡牌基类:
	if deck_type == 卡牌基类.CardType.非遗牌:
		# 必须指定地区且该地区有牌才能抽
		var region_name = MapSection.REGION.find_key(region)
		if 地区非遗牌库.has(region) and 地区非遗牌库[region].size() > 0:
			var card := 地区非遗牌库[region].pop_back() as 非遗牌
			return _deliver_drawn_feiyi(player, card, region, collection_cost, reveal_feiyi_detail)
		else:
			print("抽牌失败：", region_name, " 地区的非遗牌已被抽空！")
			return null
	elif deck_type == 卡牌基类.CardType.食物牌 and 食物牌库.size() > 0:
		var card = 食物牌库.pop_back()
		add_food_card(player, card)
		print(player.player_name, " 获得了食物牌：【", card.card_name,"】")
		if hud != null:
			hud._update_game_informs(player.player_name + " 获得了【" + card.card_name + "】！")
		return card
	elif deck_type == 卡牌基类.CardType.事件牌:
		return draw_event_card(player)
	else:
		print("牌库 [", deck_type, "] 已空！")
		return null

func draw_event_card(player: PlayerClass) -> 事件牌:
	if 事件牌库.is_empty():
		return null
	var card: 事件牌 = 事件牌库.pop_back()
	event_on_trigger.emit(card.card_name)
	print(player.player_name, " 抽到了事件牌：【", card.card_name, "】")
	if hud != null:
		hud._update_game_informs(player.player_name + " 抽到了事件牌：【" + card.card_name + "】！")
	return card

## 实际玩法入口：魔术博主先查看牌堆顶最多三张，选择一张后才公开事件。
func draw_event_card_with_profession(player: PlayerClass) -> 事件牌:
	if 事件牌库.is_empty():
		return null
	if not ProfessionManager.can_reorder_draws(player) or 事件牌库.size() <= 1:
		return draw_event_card(player)
	var deck_generation: int = _deck_build_generation
	var candidates: Array = _take_top_cards(事件牌库, ProfessionManager.get_draw_count(player))
	var result: ProfessionDrawResult = await _request_profession_draw_choice(player, candidates, &"event")
	if deck_generation != _deck_build_generation:
		return null
	var selected := _commit_profession_draw(事件牌库, candidates, result) as 事件牌
	if selected == null:
		return null
	event_on_trigger.emit(selected.card_name)
	print(player.player_name, " 抽到了事件牌：【", selected.card_name, "】")
	if hud != null:
		hud._update_game_informs(player.player_name + " 抽到了事件牌：【" + selected.card_name + "】！")
	return selected

func _request_profession_draw_choice(player: PlayerClass, candidates: Array, deck_kind: StringName) -> ProfessionDrawResult:
	var owns_modal: bool = bool(TurnManager.GameOn)
	var turn_session_generation: int = TurnManager.get_session_generation()
	var turn_epoch: int = TurnManager.get_turn_epoch()
	var modal_lease: int = -1
	if owns_modal:
		modal_lease = TurnManager.acquire_modal(
			&"profession_draw_choice",
			TurnManager.ModalResumePolicy.RESUME_REMAINING
		)
	var result: ProfessionDrawResult = await ProfessionManager.request_draw_choice(player, candidates, deck_kind)
	var same_context: bool = (
		turn_session_generation == TurnManager.get_session_generation()
		and turn_epoch == TurnManager.get_turn_epoch()
	)
	if owns_modal and modal_lease >= 0 and same_context:
		TurnManager.release_modal(modal_lease)
	if not same_context:
		return ProfessionDrawResult.new(null, [], true)
	return result

func _take_top_cards(deck: Array, count: int) -> Array:
	var cards: Array = []
	for _index: int in mini(maxi(count, 0), deck.size()):
		cards.append(deck.pop_back())
	return cards

## UI 中的第一张是下一张牌堆顶；数组末端才是实际牌顶，因此按反序追加。
func _restore_top_order(deck: Array, cards_in_draw_order: Array) -> void:
	for index: int in range(cards_in_draw_order.size() - 1, -1, -1):
		var card = cards_in_draw_order[index]
		if card != null and not deck.has(card):
			deck.append(card)

func _commit_profession_draw(deck: Array, candidates: Array, result: ProfessionDrawResult):
	if result == null or result.cancelled or result.selected_card == null or not candidates.has(result.selected_card):
		_restore_top_order(deck, candidates)
		return null
	_restore_top_order(deck, result.return_order)
	return result.selected_card

func _deliver_drawn_feiyi(
	player: PlayerClass,
	card: 非遗牌,
	region: MapSection.REGION,
	collection_cost: int,
	reveal_feiyi_detail: bool
) -> 非遗牌:
	if card == null:
		return null
	add_feiyi_card(player, card, true, reveal_feiyi_detail)
	var region_name = MapSection.REGION.find_key(region)
	print(player.player_name, " 在 [", region_name, "] 获得了非遗牌：【", card.card_name,"】")
	if hud != null:
		var collection_message := "%s 免费收集了非遗！" % player.player_name if collection_cost <= 0 else "%s 消耗%d点精力，收集了非遗！" % [player.player_name, collection_cost]
		if card.category == 非遗牌.CardCategory.节日庆典:
			hud._update_game_informs(collection_message + "\n 获得了【" + card.card_name + "】！")
			hud.information.text += "\n获得节日庆典类非遗牌，立即获得%d点精力和%d积分点！" % [FESTIVAL_ENERGY_GAIN, FESTIVAL_MONEY_GAIN]
		else:
			hud._update_game_informs(collection_message + "\n\n 获得了【" + card.card_name + "】！")
	return card

## 食物效果专用的免费地区抽牌：不消耗精力、不触发魔术博主三选一，
## 也不写入“上次成功收集的非遗点”；节日庆典的获得奖励仍正常结算。
func draw_regional_feiyi_free(player: PlayerClass, region: MapSection.REGION, reveal_detail: bool = true) -> 非遗牌:
	if player == null or not 地区非遗牌库.has(region) or 地区非遗牌库[region].is_empty():
		return null
	var card := 地区非遗牌库[region].pop_back() as 非遗牌
	_deliver_drawn_feiyi(player, card, region, 0, reveal_detail)
	if card.category == 非遗牌.CardCategory.节日庆典:
		modify_energy(player, FESTIVAL_ENERGY_GAIN, "获得节日庆典类非遗牌")
		modify_money(player, FESTIVAL_MONEY_GAIN, "获得节日庆典类非遗牌")
	return card

func discard_event(card: 事件牌) -> void:
	if card != null and card.has_meta(&"generated_by_food"):
		return
	if card != null and not 事件弃牌堆.has(card):
		事件弃牌堆.append(card)

# 3. 积分与经济结算 (中央银行)
func modify_money(player: PlayerClass, amount: int, reason: String = "无", ignore_loss_immunity: bool = false) -> bool:
	if amount < 0 and not ignore_loss_immunity and EventManager.is_loss_immune(player):
		if hud != null:
			hud._update_game_informs("【紧急避险】免疫了 %s。" % reason)
		return false
	var previous_money: int = player.current_money
	player.current_money += amount
	money_changed.emit(player, previous_money, player.current_money, reason)
	# 如果金额是负数且不够扣，可以在这里进行破产拦截
	if hud != null:
		hud._update_player_stats(player)
	print(player.player_name, " 积分点 ", amount, "。当前积分点: ", player.current_money, "。原因: ", reason)
	return true

func modify_energy(player: PlayerClass, amount: int, reason: String = "", ignore_loss_immunity: bool = false) -> bool:
	if amount < 0 and not ignore_loss_immunity and EventManager.is_loss_immune(player):
		if hud != null:
			hud._update_game_informs("【紧急避险】免疫了 %s。" % reason)
		return false
	# 判定精力上限
	var old_energy: int = player.current_energy
	var new_energy: int = clampi(old_energy + amount, 0, player.max_energy)
	
	if old_energy == new_energy:
		return false # 没有发生实际改变（比如已经满了，或者已经扣到0了）
		
	player.current_energy = new_energy
	energy_changed.emit(player, old_energy, new_energy, reason)
	print(player.player_name, " 精力变动: ", amount, "。当前精力: ", player.current_energy, "。原因: ", reason)
	if hud != null:
		hud._update_player_stats(player)
	return true

func get_feiyi(player: PlayerClass, section: MapSection, energy_cost: int = 1) -> 卡牌基类:
	energy_cost = maxi(energy_cost, 0)
	if player.current_energy < energy_cost or not has_feiyi_in_region(section.region):
		return null

	# 原型已将收集非遗的消耗调整为 1 点精力，保持与实际游戏一致。
	if energy_cost > 0:
		modify_energy(player, -energy_cost, "收集非遗")
	var card := draw_card(player, 卡牌基类.CardType.非遗牌, section.region, energy_cost, true) as 非遗牌
	if card == null:
		# 牌库在抽取前被其他逻辑清空时，返还本次未完成收集的消耗。
		if energy_cost > 0:
			modify_energy(player, energy_cost, "收集非遗失败返还")
		return null
	if card.category == 非遗牌.CardCategory.节日庆典:
		modify_energy(player, FESTIVAL_ENERGY_GAIN, "获得节日庆典类非遗牌")
		modify_money(player, FESTIVAL_MONEY_GAIN, "获得节日庆典类非遗牌")
	player.last_successful_feiyi_section = section
	return card

## 玩家实际抽取入口；普通职业沿用单抽，魔术博主以原子事务完成三选一及回顶排序。
func get_feiyi_with_profession(player: PlayerClass, section: MapSection, energy_cost: int = 1) -> 非遗牌:
	energy_cost = maxi(energy_cost, 0)
	if player == null or section == null or player.current_energy < energy_cost or not has_feiyi_in_region(section.region):
		return null
	var deck: Array = 地区非遗牌库[section.region]
	if not ProfessionManager.can_reorder_draws(player) or deck.size() <= 1:
		return get_feiyi(player, section, energy_cost) as 非遗牌
	var deck_generation: int = _deck_build_generation
	var candidates: Array = _take_top_cards(deck, ProfessionManager.get_draw_count(player))
	var result: ProfessionDrawResult = await _request_profession_draw_choice(player, candidates, &"feiyi")
	if deck_generation != _deck_build_generation:
		return null
	var card := _commit_profession_draw(deck, candidates, result) as 非遗牌
	if card == null:
		return null
	if energy_cost > 0:
		modify_energy(player, -energy_cost, "收集非遗")
	_deliver_drawn_feiyi(player, card, section.region, energy_cost, true)
	if card.category == 非遗牌.CardCategory.节日庆典:
		modify_energy(player, FESTIVAL_ENERGY_GAIN, "获得节日庆典类非遗牌")
		modify_money(player, FESTIVAL_MONEY_GAIN, "获得节日庆典类非遗牌")
	player.last_successful_feiyi_section = section
	return card

# 4. 业务逻辑封装：处理打工发工资
func process_work_salary(player: PlayerClass, work_turn: int) -> bool:
	if player == null:
		return false
	var work_energy_cost: int = ProfessionManager.get_work_energy_cost(player)
	if player.current_energy < work_energy_cost:
		return false
	var salary: int = 0
	# 严格按照说明书规则发放打工积分 [cite: 85]
	match work_turn:
		1: salary = 250
		2: salary = 300
		3: salary = 350
		_:
			push_error("ResourceManager.process_work_salary: 非法的打工轮数。")
			return false
	salary = FoodManager.adjust_work_income(player, salary)
		
	if work_energy_cost > 0:
		modify_energy(player, -work_energy_cost, "打工消耗")
	modify_money(player, salary, "打工第 " + str(work_turn) + " 回合工资")
	work_completed.emit(player, work_turn, salary)
	if work_energy_cost == 0 and ProfessionManager.is_skill_enabled(player, PlayerClass.PlayerCharacter.生活博主):
		ProfessionManager.notify_skill_triggered(player, "打工不消耗精力")
	if hud != null:
		var food_effect_message := FoodManager.get_work_income_effect_message(player)
		if not food_effect_message.is_empty():
			hud.information.text += "\n" + food_effect_message
		if work_energy_cost == 0:
			hud.information.text += "\n【生活博主】打工免耗，积分点 +%d" % salary
		else:
			hud.information.text += "\n%s消耗%d点精力，积分点 +%d" % [player.player_name, work_energy_cost, salary]
	return true

func vis_scenery(player: PlayerClass, section: MapSection) -> bool:
	var achievement_manager: Node = get_node_or_null("/root/AchievementManager")
	if achievement_manager != null and not bool(achievement_manager.call("record_scenery_check_in", player, section)):
		return false
	if not is_instance_valid(player):
		return false
	modify_energy(player, 3, "看风景")
	var travel_reward: int = ProfessionManager.get_scenery_arrival_money(player)
	var travel_reward_applied := ProfessionManager.record_scenery_arrival(player, section, &"normal")
	var result_message := player.player_name + " 欣赏风景，回复3点精力！"
	if travel_reward_applied:
		result_message = "%s 欣赏风景，回复3点精力，获得%d积分点！" % [player.player_name, travel_reward]
	print(result_message)
	if hud != null:
		hud._update_game_informs(result_message)
	return true

# 5. 业务逻辑封装：商店购买食物
func buy_food(player: PlayerClass, food_card: 食物牌) -> bool:
	if player.食物牌手牌.has(food_card):
		return false
	var cost: int = food_card.cost
	if player.current_money >= cost:
		modify_money(player, -cost, "购买食物")
		add_food_card(player, food_card)
		食物牌库.erase(food_card)
		food_purchased.emit(player, food_card, cost)
		return true
	else:
		print(player.player_name, " 积分不足，无法购买！")
		return false

func consume_food(player: PlayerClass, food_card: 食物牌, option_id: int = -1) -> bool:
	# 兼容旧版同步调用与既有市级回归测试；完整食物 UI 统一 await FoodManager.consume_food()。
	if not player.食物牌手牌.has(food_card):
		return false
	if not food_card.can_use(player):
		return false
	if food_card.food_type != 食物牌.FoodType.市级:
		return false
	var is_extra_food_use: bool = player.food_used_count_this_turn >= ProfessionManager.BASE_FOOD_USE_LIMIT \
		and ProfessionManager.is_skill_enabled(player, PlayerClass.PlayerCharacter.美食博主)
	modify_energy(player, 2, "食物：%s" % food_card.card_name)
	player.food_used_count_this_turn += 1
	if is_extra_food_use:
		ProfessionManager.notify_skill_triggered(player, "额外享用食物")
	remove_food_card(player, food_card)
	# 已使用的食物牌回到牌库；必须在真正消费后才回收，避免同一张牌同时在手牌和牌库中。
	return_food_to_bottom(food_card)
	var achievement_manager: Node = get_node_or_null("/root/AchievementManager")
	if achievement_manager != null:
		achievement_manager.call("record_food_consumed", player, food_card)
	return true

func return_food_to_bottom(card: 食物牌) -> void:
	if card != null and not 食物牌库.has(card):
		食物牌库.insert(0, card)

## 从牌堆顶向下按等级抽取，不改变未命中牌的相对顺序。
## levels 为空表示全部等级；抽出的牌在调用方完成获得动画后加入手牌。
func draw_food_cards_filtered(count: int, levels: Array = []) -> Array[食物牌]:
	var result: Array[食物牌] = []
	if count <= 0:
		return result
	var index := 食物牌库.size() - 1
	while index >= 0 and result.size() < count:
		var card := 食物牌库[index] as 食物牌
		if card != null and (levels.is_empty() or levels.has(card.food_type)):
			result.append(card)
			食物牌库.remove_at(index)
		index -= 1
	return result

func get_score_breakdown(player: PlayerClass) -> Dictionary:
	var base_score: int = 0
	var categories: Dictionary[非遗牌.CardCategory, int] = {}
	var regions: Dictionary[MapSection.REGION, int] = {}
	var category_combo_bonus: int = 0
	var category_completion_bonus: int = 0
	var region_combo_bonus: int = 0
	var region_completion_bonus: int = 0
	var region_annotations: Dictionary = {}
	for card:非遗牌 in player.非遗牌手牌:
		base_score += card.base_score
		
		categories[card.category] = categories.get(card.category, 0) + 1
		regions[card.region] = regions.get(card.region, 0) + 1

	# 类别组合分取单个类别中可达成的最高档位，不能由遍历顺序决定。
	for category:非遗牌.CardCategory in categories:
		var category_count: int = categories[category]
		category_combo_bonus = maxi(category_combo_bonus, _get_category_combo_bonus(category_count))
		var category_total: int = 类别非遗牌上限字典.get(category, 0)
		if category_total > 0 and category_count >= category_total:
			category_completion_bonus += 5

	if categories.size() >= 5:
		category_combo_bonus += 5

	# 每个满足条件的城市分别计算“同城 5 张”和“集齐全市”；江汉三市仍只计一次。
	# 按枚举顺序遍历，保证多城同时达成时的显示不受 Dictionary 顺序影响。
	for region_value in range(MapSection.REGION.size()):
		var region: MapSection.REGION = region_value
		if not regions.has(region):
			continue
		var region_count: int = regions[region]
		if region_count >= 5:
			region_combo_bonus += 5
			_add_region_score_annotation(region_annotations, region, "触发同城5张得分+5")
		var region_total: int = 地区非遗牌上限字典.get(region, 0)
		if region_total > 0 and region_count >= region_total:
			region_completion_bonus += 2
			_add_region_score_annotation(region_annotations, region, "触发集齐全市得分+2")

	if regions.has(MapSection.REGION.潜江) and regions.has(MapSection.REGION.天门) and regions.has(MapSection.REGION.仙桃):
		region_completion_bonus += 2
		for trio_region: MapSection.REGION in [MapSection.REGION.潜江, MapSection.REGION.天门, MapSection.REGION.仙桃]:
			_add_region_score_annotation(region_annotations, trio_region, "触发江汉三市得分+2（合计）")

	var regional_combo_score := region_combo_bonus + region_completion_bonus
	var achievement_score: int = 0
	var achievements: Array = []
	var achievement_manager: Node = get_node_or_null("/root/AchievementManager")
	if achievement_manager != null:
		achievement_score = int(achievement_manager.call("get_achievement_score", player))
		achievements = achievement_manager.call("get_owned_achievements", player)
	return {
		"base_score": base_score,
		"category_combo_score": category_combo_bonus,
		"category_completion_score": category_completion_bonus,
		"regional_combo_score": regional_combo_score,
		"achievement_score": achievement_score,
		"achievements": achievements,
		"total_score": base_score + category_combo_bonus + category_completion_bonus + regional_combo_score + achievement_score,
		"region_annotations": region_annotations,
	}

func _add_region_score_annotation(annotations: Dictionary, region: MapSection.REGION, text: String) -> void:
	if not annotations.has(region):
		annotations[region] = []
	annotations[region].append(text)

func calculate_victory_score(player: PlayerClass) -> void:
	var breakdown := get_score_breakdown(player)
	var previous_score: int = player.current_score
	player.current_score = int(breakdown.get("total_score", 0))
	if previous_score != player.current_score:
		score_changed.emit(player, previous_score, player.current_score, breakdown.duplicate(true))
	if hud != null:
		hud._update_player_stats(player)

func _get_category_combo_bonus(card_count: int) -> int:
	if card_count >= 10:
		return 5
	if card_count >= 5:
		return 3
	if card_count >= 3:
		return 2
	return 0

func draw_shop_foods(count: int = 3) -> Array[食物牌]:
	var foods: Array[食物牌] = []
	# 保证牌库有足够的牌，不够就把所有的拿出来
	var actual_count = min(count, 食物牌库.size())
	for i in range(actual_count):
		# 注意这里是弹出，因为摆在货架上的牌就不在牌库里了
		foods.append(食物牌库.pop_back() as 食物牌) 
	return foods

## 将未购买的货架牌按展示顺序放回牌堆底；牌堆顶位于数组末端。
## 依次插入索引 0 后，未来从牌堆顶抽取时仍会得到原展示顺序。
func return_shop_foods_to_bottom(cards: Array[食物牌]) -> void:
	for card: 食物牌 in cards:
		return_food_to_bottom(card)

func use_feiyi(player: PlayerClass, card:非遗牌) -> bool:
	if not player.非遗牌手牌.has(card):
		return false
	if card.category == 非遗牌.CardCategory.手工技艺 and player.handicraft_used_this_moving:
		if hud != null:
			hud._update_game_informs("本移动阶段已使用过手工技艺牌。")
		return false
	if not card.can_use(player):
		if hud != null:
			hud._update_game_informs("【" + card.card_name + "】当前不能使用。")
		return false
	feiyi_execute_effect(player, card)
	desert_feiyi(player, card)
	return true

func feiyi_execute_effect(player: PlayerClass, card:非遗牌) -> void:
	print("执行了非遗牌效果：", card.card_name)
	match card.category:
		非遗牌.CardCategory.戏曲表演:
			ResourceManager.modify_energy(player, 3, "使用戏曲表演类非遗牌")
			if hud != null:
				hud._update_game_informs("使用"+非遗牌.CardCategory.find_key(card.category)+"类非遗牌【"+card.card_name+"】，回复3点精力！")
		非遗牌.CardCategory.民间音乐:
			ResourceManager.modify_money(player, FOLK_MUSIC_MONEY_GAIN, "使用民间音乐类非遗牌")
			if hud != null:
				hud._update_game_informs("使用"+非遗牌.CardCategory.find_key(card.category)+"类非遗牌【"+card.card_name+"】，获得%d积分点！" % FOLK_MUSIC_MONEY_GAIN)
		非遗牌.CardCategory.手工技艺:
			player.handicraft_used_this_moving = true
			if not player.movement_multiplier_applied:
				player.maxMove *= 2
				player.movement_multiplier_applied = true
			if hud != null:
				hud._update_player_stats(player)
				hud.information.text += ("\n使用"+非遗牌.CardCategory.find_key(card.category)+"类非遗牌【"+card.card_name+"】，最大可移动步数翻倍！")
			if player.map != null:
				player.map._clear_all_highlights()
				player.map._show_reachable_areas()
		_:
			pass

func desert_feiyi(player:PlayerClass, card:非遗牌) -> void:
	if remove_feiyi_card(player, card):
		MarketManager.deposit_card(card, &"used_or_discarded")

func find_winner() -> Array[PlayerClass]:
	var maxScore = -1
	var winners:Array[PlayerClass] = []
	for player in TurnManager.players:
		if player.current_score > maxScore:
			maxScore = player.current_score
			winners.clear()
			winners.append(player)
		elif  player.current_score == maxScore:
			winners.append(player)
	return winners
