extends Node
signal event_on_trigger(event_name: String)
# 全局牌库
var 非遗牌库: Array[卡牌基类] = []
var 食物牌库: Array[卡牌基类] = []
var 事件牌库: Array[卡牌基类] = []
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
	hud = get_tree().get_first_node_in_group("HUD")

var 地区非遗牌库: Dictionary[MapSection.REGION, Array] = {} 

func _init_decks():
	# 调用新的分地区加载函数
	_load_regional_feiyi_cards("res://Cards/非遗牌")
	
	# 其他普通牌库保持原样加载
	_load_cards_from_dir("res://Cards/食物牌", 食物牌库)
	_load_cards_from_dir("res://Cards/事件牌", 事件牌库)
	食物牌库.shuffle()
	事件牌库.shuffle()

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
				地区非遗牌库[STRING_TO_REGION[folder_name]] = cards_array # 存入字典
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
		
# 【新增】：提供给外部查询该地区是否还有牌的接口
func has_feiyi_in_region(region:MapSection.REGION) -> bool:
	if 地区非遗牌库.has(region):
		return 地区非遗牌库[region].size() > 0
	return false
# 2. 发牌中心
func draw_card(player: PlayerClass, deck_type: 卡牌基类.CardType, region:MapSection.REGION) -> 卡牌基类:
	if deck_type == 卡牌基类.CardType.非遗牌:
		# 必须指定地区且该地区有牌才能抽
		var region_name = MapSection.REGION.find_key(region)
		if 地区非遗牌库.has(region) and 地区非遗牌库[region].size() > 0:
			var card = 地区非遗牌库[region].pop_back()
			player.非遗牌手牌.append(card)
			print(player.player_name, " 在 [", region_name, "] 获得了非遗牌：【", card.card_name,"】")
			hud._update_game_informs(player.player_name + " 消耗1点精力，收集了非遗！\n\n 获得了【" + card.card_name + "】！")
			return card
		else:
			print("抽牌失败：", region_name, " 地区的非遗牌已被抽空！")
			return null
	elif deck_type == 卡牌基类.CardType.食物牌 and 食物牌库.size() > 0:
		var card = 食物牌库.pop_back()
		player.食物牌手牌.append(card)
		print(player.player_name, " 获得了食物牌：【", card.card_name,"】")
		hud._update_game_informs(player.player_name + " 获得了【" + card.card_name + "】！")
		return card
	elif deck_type == 卡牌基类.CardType.事件牌 and 事件牌库.size() > 0:
		var card = 事件牌库.pop_back()
		event_on_trigger.emit(card.card_name)
		print(player.player_name, " 抽到了事件牌：【", card.card_name,"】")
		hud._update_game_informs(player.player_name + " 抽到了事件牌：【" + card.card_name + "】！")
		return card
	else:
		print("牌库 [", deck_type, "] 已空！")
		return null

# 3. 积分与经济结算 (中央银行)
func modify_money(player: PlayerClass, amount: int, reason: String = "无"):
	player.current_money += amount
	# 如果金额是负数且不够扣，可以在这里进行破产拦截
	print(player.player_name, " 积分点 ", amount, "。当前积分点: ", player.current_money, "。原因: ", reason)

func modify_energy(player: PlayerClass, amount: int, reason: String = "") -> bool:
	# 判定精力上限
	var new_energy = clampi(player.current_energy + amount, 0, player.max_energy)
	
	if player.current_energy == new_energy:
		return false # 没有发生实际改变（比如已经满了，或者已经扣到0了）
		
	player.current_energy = new_energy
	print(player.player_name, " 精力变动: ", amount, "。当前精力: ", player.current_energy, "。原因: ", reason)
	
	return true

func get_feiyi(player: PlayerClass, section: MapSection) -> 卡牌基类:
	modify_energy(player, -1, "收集非遗")
	var region = section.region
	return draw_card(player, 卡牌基类.CardType.非遗牌, section.region)
	

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
	hud._update_player_stats(player)

func vis_scenery(player: PlayerClass, section: MapSection) -> bool:
	var region = section.region
	player.current_energy = clampi(player.current_energy + 3, 0, player.max_energy)
	print(player.player_name, " 欣赏风景，回复3点精力，并获得风景明信片！")
	hud._update_game_informs(player.player_name + " 欣赏风景，回复3点精力！")
	# TODO: 获得明信片的接口
	return true

# 5. 业务逻辑封装：商店购买食物
func buy_food(player: PlayerClass, food_card: 食物牌) -> bool:
	# 假设 food_card 内部有 cost 属性，根据说明书，市级100、省级150、国家级200积分 [cite: 56]
	var cost = food_card.cost 
	if player.current_money >= cost:
		modify_money(player, -cost, "购买食物")
		player.食物牌手牌.append(food_card)
		食物牌库.erase(food_card)
		return true
	else:
		print(player.player_name, " 积分不足，无法购买！")
		return false

func calculate_victory_score(score: PlayerClass):
	pass
