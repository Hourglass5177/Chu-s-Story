extends Node2D
signal game_start
#@onready var tile_map = $MapBackground/TileMapLayer
#@onready var player = $Player
var player_data: Array
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	#var players: Array[PlayerClass] = [$Player, $Player2]
	#$Player.start_coord = Vector3i(0,0,0)
	#$Player2.start_coord = Vector3i(7, -6, -1)
	#TurnManager.start_game(players)
	await init_game()

func init_game() -> void:
	var players: Array[PlayerClass] = []
	var player_scene: PackedScene = preload("res://Players/player.tscn")
	var active_setup: SessionSetup = GameManager.get_active_session_setup()
	if active_setup != null:
		player_data = active_setup.to_legacy_player_data()
		for config: PlayerSetup in active_setup.players:
			var new_player: PlayerClass = player_scene.instantiate() as PlayerClass
			_apply_typed_player_setup(new_player, config)
			add_child(new_player)
			players.append(new_player)
	else:
		# 模拟器与旧菜单仍可直接写入 player_data；没有强类型快照时保持原通路。
		player_data = GameManager.player_data
		for config: Dictionary in player_data:
			var new_player: PlayerClass = player_scene.instantiate() as PlayerClass
			_apply_legacy_player_setup(new_player, config, players.size())
			add_child(new_player)
			players.append(new_player)
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


func _apply_typed_player_setup(player: PlayerClass, config: PlayerSetup) -> void:
	player.player_name = config.normalized_display_name()
	player.player_types = config.profession_type as PlayerClass.PlayerCharacter
	player.start_coord = MapSection.出生点坐标[config.starting_region]
	player.player_index = config.slot_index
	player.is_bot = config.is_bot()


func _apply_legacy_player_setup(player: PlayerClass, config: Dictionary, index: int) -> void:
	player.player_name = String(config["name"])
	player.player_types = PlayerClass.PlayerCharacter.get(String(config["job"]))
	var region: MapSection.REGION = MapSection.REGION.get(String(config["location"]))
	player.start_coord = MapSection.出生点坐标[region]
	player.player_index = index
	player.is_bot = bool(config.get("is_bot", false))
