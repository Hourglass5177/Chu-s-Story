extends Node2D
signal game_start
#@onready var tile_map = $MapBackground/TileMapLayer
#@onready var player = $Player
var player_data:Array
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	#var players: Array[PlayerClass] = [$Player, $Player2]
	#$Player.start_coord = Vector3i(0,0,0)
	#$Player2.start_coord = Vector3i(7, -6, -1)
	#TurnManager.start_game(players)
	init_game()

func init_game():
	player_data = GameManager.player_data
	var players:Array[PlayerClass] = []
	var player_scene = preload("res://Players/player.tscn")
	var idx = 0
	for config in player_data:
		var new_player = player_scene.instantiate() as PlayerClass
		# 2. 赋予基础属性
		new_player.player_name = config["name"]
		# 【核心转换 1】：将字符串转回职业枚举
		# config["job"] 是 "商业博主" 等中文字符串
		# PlayerCharacter.get() 可以安全地把字符串键转换为对应的整数枚举值
		new_player.player_types = PlayerClass.PlayerCharacter.get(config["job"])
		var birth_coord:Vector3i = MapSection.出生点坐标[MapSection.REGION.get(config["location"])]
		new_player.start_coord = birth_coord
		new_player.player_index = idx
		# 3. 将新玩家加入场景树（必须先 add_child，节点内部的 _ready 才会执行，后续操作才安全）
		add_child(new_player)
		# 获取字符串对应的地区枚举
		players.append(new_player)
		idx += 1
	var current_hud = get_tree().get_first_node_in_group("HUD")
	if current_hud == null:
		push_error("致命错误：MainMap 场景里没有找到归属于 HUD 组的节点！")
		return
	# 2. 【核心修复：依赖注入】主动将 HUD 的控制权分发给所有全局单例！
	ResourceManager.hud = current_hud
	TurnManager.hud = current_hud
	EventManager.bind_runtime(current_hud, current_hud.get_event_overlay())
	await get_tree().process_frame
	TurnManager.map = get_tree().get_first_node_in_group("MAP")
	TurnManager.start_game(players)
	AchievementManager.bind_map(TurnManager.map)
