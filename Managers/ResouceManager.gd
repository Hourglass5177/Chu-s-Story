extends Node
signal event_on_trigger(event_name: String)
# 全局牌库
var 非遗牌库: Array[卡牌基类] = []
var 食物牌库: Array[卡牌基类] = []
var 事件牌库: Array[事件牌] = []
var 事件弃牌堆: Array[事件牌] = []
var 地区非遗牌上限字典: Dictionary[MapSection.REGION, int] = {}
var 类别非遗牌上限字典: Dictionary[非遗牌.CardCategory, int] = {}
var hud:HUD

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

func _ready():
	_init_decks()
	#hud = get_tree().get_first_node_in_group("HUD")
	

var 地区非遗牌库: Dictionary[MapSection.REGION, Array] = {} 

func _init_decks():
	# 调用新的分地区加载函数
	_load_regional_feiyi_cards("res://Cards/非遗牌")
	
	# 其他普通牌库保持原样加载
	_load_cards_from_dir("res://Cards/食物牌", 食物牌库)
	_load_event_cards("res://Cards/事件牌")
	_count_feiyi_in_category()
	非遗牌库.shuffle()
	食物牌库.shuffle()
	事件牌库.shuffle()
	事件弃牌堆.clear()

func _load_event_cards(path: String) -> void:
	事件牌库.clear()
	var loaded: Array = []
	_load_cards_from_dir(path, loaded)
	for card in loaded:
		if card is 事件牌 and card.is_available():
			事件牌库.append(card as 事件牌)

# 【新增】：专门读取地区子文件夹的逻辑
func _load_regional_feiyi_cards(base_path: String):
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
				cards_array.shuffle() # 仅对该地区洗牌
				非遗牌库.append_array(cards_array)
				地区非遗牌库[STRING_TO_REGION[folder_name]] = cards_array # 存入字典
				地区非遗牌上限字典[STRING_TO_REGION[folder_name]] = cards_array.size()
				print("已加载地区 [", folder_name, "] 非遗牌库，共 ", cards_array.size(), " 张")
	else:
		push_warning("警告：找不到非遗牌根目录 -> ", base_path)
		
func _load_cards_from_dir(path: String, target_array: Array):
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

func _count_feiyi_in_category():
	for card:非遗牌 in 非遗牌库:
		if 类别非遗牌上限字典.has(card.category):
			类别非遗牌上限字典[card.category] += 1
		else: 类别非遗牌上限字典[card.category] = 1

# 【新增】：提供给外部查询该地区是否还有牌的接口
func has_feiyi_in_region(region:MapSection.REGION) -> bool:
	if 地区非遗牌库.has(region):
		return 地区非遗牌库[region].size() > 0
	return false
# 2. 发牌中心
func draw_card(player: PlayerClass, deck_type: 卡牌基类.CardType, region: MapSection.REGION, collection_cost: int = 1) -> 卡牌基类:
	if deck_type == 卡牌基类.CardType.非遗牌:
		# 必须指定地区且该地区有牌才能抽
		var region_name = MapSection.REGION.find_key(region)
		if 地区非遗牌库.has(region) and 地区非遗牌库[region].size() > 0:
			var card = 地区非遗牌库[region].pop_back()
			player.非遗牌手牌.append(card)
			print(player.player_name, " 在 [", region_name, "] 获得了非遗牌：【", card.card_name,"】")
			if hud != null:
				var collection_message := "%s 免费收集了非遗！" % player.player_name if collection_cost <= 0 else "%s 消耗%d点精力，收集了非遗！" % [player.player_name, collection_cost]
				if card.category == 非遗牌.CardCategory.节日庆典:
					hud._update_game_informs(collection_message + "\n 获得了【" + card.card_name + "】！")
					hud.information.text += "\n获得节日庆典类非遗牌，立即获得3点精力和750积分点！"
				else:
					hud._update_game_informs(collection_message + "\n\n 获得了【" + card.card_name + "】！")
				hud.refresh_feiyi_list(player)
			return card
		else:
			print("抽牌失败：", region_name, " 地区的非遗牌已被抽空！")
			return null
	elif deck_type == 卡牌基类.CardType.食物牌 and 食物牌库.size() > 0:
		var card = 食物牌库.pop_back()
		player.食物牌手牌.append(card)
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

func discard_event(card: 事件牌) -> void:
	if card != null and not 事件弃牌堆.has(card):
		事件弃牌堆.append(card)

# 3. 积分与经济结算 (中央银行)
func modify_money(player: PlayerClass, amount: int, reason: String = "无", ignore_loss_immunity: bool = false) -> bool:
	if amount < 0 and not ignore_loss_immunity and EventManager.is_loss_immune(player):
		if hud != null:
			hud._update_game_informs("【紧急避险】免疫了 %s。" % reason)
		return false
	player.current_money += amount
	# 如果金额是负数且不够扣，可以在这里进行破产拦截
	if hud != null:
		hud._update_player_stats(player)
	print(player.player_name, " 积分点 ", amount, "。当前积分点: ", player.current_money, "。原因: ", reason)
	return true

func modify_energy(player: PlayerClass, amount: int, reason: String = "") -> bool:
	if amount < 0 and EventManager.is_loss_immune(player):
		if hud != null:
			hud._update_game_informs("【紧急避险】免疫了 %s。" % reason)
		return false
	# 判定精力上限
	var new_energy = clampi(player.current_energy + amount, 0, player.max_energy)
	
	if player.current_energy == new_energy:
		return false # 没有发生实际改变（比如已经满了，或者已经扣到0了）
		
	player.current_energy = new_energy
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
	var card := draw_card(player, 卡牌基类.CardType.非遗牌, section.region, energy_cost) as 非遗牌
	if card == null:
		# 牌库在抽取前被其他逻辑清空时，返还本次未完成收集的消耗。
		if energy_cost > 0:
			modify_energy(player, energy_cost, "收集非遗失败返还")
		return null
	if card.category == 非遗牌.CardCategory.节日庆典:
		modify_energy(player, 3, "获得节日庆典类非遗牌")
		modify_money(player, 750, "获得节日庆典类非遗牌")
	player.last_successful_feiyi_section = section
	return card

# 4. 业务逻辑封装：处理打工发工资
func process_work_salary(player: PlayerClass, work_turn: int):
	var salary = 0
	# 严格按照说明书规则发放打工积分 [cite: 85]
	match work_turn:
		1: salary = 250
		2: salary = 300
		3: salary = 350
		_: push_error("非法的打工轮数！")
		
	# 打工消耗 1 点精力 [cite: 43]
	modify_energy(player, -1, "打工消耗")
	modify_money(player, salary, "打工第 " + str(work_turn) + " 回合工资")
	hud.information.text += "\n"+player.player_name+"消耗1点精力，积分点 +"+str(salary)

func vis_scenery(player: PlayerClass, section: MapSection) -> bool:
	var region = section.region
	await get_tree().create_timer(1).timeout
	modify_energy(player, 3, "看风景")
	print(player.player_name, " 欣赏风景，回复3点精力，并获得风景明信片！")
	hud._update_game_informs(player.player_name + " 欣赏风景，回复3点精力！")
	# TODO: 获得明信片的接口
	return true

# 5. 业务逻辑封装：商店购买食物
func buy_food(player: PlayerClass, food_card: 食物牌) -> bool:
	if player.食物牌手牌.has(food_card):
		return false
	var cost: int = food_card.cost
	if player.current_money >= cost:
		modify_money(player, -cost, "购买食物")
		player.食物牌手牌.append(food_card)
		食物牌库.erase(food_card)
		return true
	else:
		print(player.player_name, " 积分不足，无法购买！")
		return false

func consume_food(player: PlayerClass, food_card: 食物牌, option_id: int = -1) -> bool:
	if not player.食物牌手牌.has(food_card):
		return false
	if not food_card.can_use(player):
		return false
	food_card.execute_effect(player, option_id)
	player.food_used_this_turn = true
	player.食物牌手牌.erase(food_card)
	# 已使用的食物牌回到牌库；必须在真正消费后才回收，避免同一张牌同时在手牌和牌库中。
	if not 食物牌库.has(food_card):
		食物牌库.insert(0, food_card)
	return true

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

	# 地域组合分同样只取“同城 5 张”一次；集齐一个城市的所有牌则各计一次。
	# 按枚举顺序遍历，保证多城同时达成时的显示不受 Dictionary 顺序影响。
	var five_card_awarded := false
	for region_value in range(MapSection.REGION.size()):
		var region: MapSection.REGION = region_value
		if not regions.has(region):
			continue
		var region_count: int = regions[region]
		if region_count >= 5 and not five_card_awarded:
			region_combo_bonus = 5
			five_card_awarded = true
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
	return {
		"base_score": base_score,
		"category_combo_score": category_combo_bonus,
		"category_completion_score": category_completion_bonus,
		"regional_combo_score": regional_combo_score,
		"total_score": base_score + category_combo_bonus + category_completion_bonus + regional_combo_score,
		"region_annotations": region_annotations,
	}

func _add_region_score_annotation(annotations: Dictionary, region: MapSection.REGION, text: String) -> void:
	if not annotations.has(region):
		annotations[region] = []
	annotations[region].append(text)

func calculate_victory_score(player: PlayerClass) -> void:
	var breakdown := get_score_breakdown(player)
	player.current_score = int(breakdown.get("total_score", 0))
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
	食物牌库.shuffle()
	for i in range(actual_count):
		# 注意这里是弹出，因为摆在货架上的牌就不在牌库里了
		foods.append(食物牌库.pop_back() as 食物牌) 
	return foods

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
			ResourceManager.modify_money(player, 750, "使用民间音乐类非遗牌")
			if hud != null:
				hud._update_game_informs("使用"+非遗牌.CardCategory.find_key(card.category)+"类非遗牌【"+card.card_name+"】，获得750积分点！")
		非遗牌.CardCategory.手工技艺:
			player.handicraft_used_this_moving = true
			player.maxMove *= 2
			if hud != null:
				hud._update_player_stats(player)
				hud.information.text += ("\n使用"+非遗牌.CardCategory.find_key(card.category)+"类非遗牌【"+card.card_name+"】，最大可移动步数翻倍！")
			if player.map != null:
				player.map._clear_all_highlights()
				player.map._show_reachable_areas()
		_:
			pass

func desert_feiyi(player:PlayerClass, card:非遗牌) -> void:
	if player.非遗牌手牌.has(card):
		player.非遗牌手牌.erase(card)
		MarketManager.deposit_card(card, &"used_or_discarded")
		calculate_victory_score(player)
		if hud != null:
			hud.refresh_feiyi_list(player)
			hud._update_player_stats(player)

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
