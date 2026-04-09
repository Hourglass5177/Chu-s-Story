extends Node
signal event_on_trigger(event_name: String)
# 全局牌库
var 非遗牌库: Array[卡牌基类] = []
var 食物牌库: Array[卡牌基类] = []
var 事件牌库: Array[卡牌基类] = []
var hud:HUD

func _ready():
	_init_decks()
	hud = get_tree().get_first_node_in_group("HUD")

# 1. 初始化并洗牌
func _init_decks():
	### 实际开发中，这里应当遍历 res://Cards/ 目录去 load 所有 .tres 文件
	# 此处为示例占位
	非遗牌库.shuffle()
	食物牌库.shuffle()
	事件牌库.shuffle()

# 2. 发牌中心
func draw_card(player: PlayerClass, deck_type: 卡牌基类.CardType) -> 卡牌基类:
	if deck_type == 卡牌基类.CardType.非遗牌 and 非遗牌库.size() > 0:
		var card = 非遗牌库.pop_back()
		player.非遗牌手牌.append(card)
		print(player.player_name, " 获得了非遗牌：【", card.card_name,"】")
		hud._update_game_informs(player.player_name + " 消耗1点精力，收集了非遗！\n\n 获得了【" + card.card_name + "】！")
		return card
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
	return draw_card(player, 卡牌基类.CardType.非遗牌)
	

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
