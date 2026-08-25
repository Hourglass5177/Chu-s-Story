extends Node

const MAIN_MENU_SCENE: String = "res://main_menu.tscn"

enum RuntimeProfile { NORMAL, HEADLESS_SIMULATION }

var player_data: Array = []
var runtime_profile: RuntimeProfile = RuntimeProfile.NORMAL
var _session_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _session_seed: int = 0
var _active_session_setup: SessionSetup = null
var _local_session_prepared: bool = false

func _ready() -> void:
	configure_session()

func configure_session(seed_value: int = -1, profile: RuntimeProfile = RuntimeProfile.NORMAL) -> int:
	runtime_profile = profile
	if seed_value < 0:
		_session_rng.randomize()
		_session_seed = _session_rng.seed
	else:
		_session_seed = seed_value
		_session_rng.seed = seed_value
	return _session_seed

func get_session_seed() -> int:
	return _session_seed

func is_headless_simulation() -> bool:
	return runtime_profile == RuntimeProfile.HEADLESS_SIMULATION

func randi_between(minimum: int, maximum: int) -> int:
	return _session_rng.randi_range(minimum, maximum)

func shuffle_array(values: Array) -> void:
	for index: int in range(values.size() - 1, 0, -1):
		var swap_index: int = _session_rng.randi_range(0, index)
		var value = values[index]
		values[index] = values[swap_index]
		values[swap_index] = value

func pick_from(values: Array):
	if values.is_empty():
		return null
	return values[_session_rng.randi_range(0, values.size() - 1)]

## Starts a fresh local session in the only safe order: choose the new world's RNG
## first, then rebuild/shuffle runtime resources with that RNG, then publish setup.
## This keeps the reported seed and the actual opening decks replayable.
func begin_local_session(setup: SessionSetup, seed_value: int = -1) -> Error:
	if setup == null or setup.mode != SessionSetup.GameMode.LOCAL:
		return ERR_INVALID_PARAMETER
	if not setup.validate().is_empty():
		return ERR_INVALID_DATA
	configure_session(seed_value, RuntimeProfile.NORMAL)
	reset_session()
	return prepare_local_session(setup)

## 原子提交本地开局配置。重复提交同一配置视为幂等成功；
## 不同配置必须先 reset_session()，避免快速重复确认覆盖已经开始加载的对局。
func prepare_local_session(setup: SessionSetup) -> Error:
	if setup == null or setup.mode != SessionSetup.GameMode.LOCAL:
		return ERR_INVALID_PARAMETER
	if not setup.validate().is_empty():
		return ERR_INVALID_DATA
	var candidate: SessionSetup = setup.duplicate_snapshot()
	candidate.normalize_display_names()
	if _local_session_prepared:
		return OK if _active_session_setup != null and _active_session_setup.is_equivalent_to(candidate) else ERR_ALREADY_EXISTS
	_active_session_setup = candidate
	player_data.assign(candidate.to_legacy_player_data())
	_local_session_prepared = true
	return OK


## 返回独立快照，调用者无法修改 GameManager 内已经提交的配置。
func get_active_session_setup() -> SessionSetup:
	return _active_session_setup.duplicate_snapshot() if _active_session_setup != null else null

## 清理上一局的全部运行时绑定。每个管理器都通过能力检查调用，便于系统分阶段接入。
func reset_session(rebuild_resources: bool = true) -> void:
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = false

	var interaction_coordinator: Node = get_node_or_null("/root/InteractionCoordinator")
	var turn_manager: Node = get_node_or_null("/root/TurnManager")
	if turn_manager != null and turn_manager.has_method("reset_session"):
		turn_manager.call("reset_session")
	else:
		# 正常工程由 TurnManager 统一取消交互；只有精简测试树没有 TurnManager 时才直接清理。
		_call_if_available(interaction_coordinator, &"reset_session")

	var resource_manager: Node = get_node_or_null("/root/ResourceManager")
	if rebuild_resources:
		_call_if_available(resource_manager, &"reset_for_new_game")
	else:
		_call_if_available(resource_manager, &"unbind_runtime")
	_clear_property_if_available(resource_manager, &"hud")

	var event_manager: Node = get_node_or_null("/root/EventManager")
	_call_if_available(event_manager, &"reset_for_new_game")
	if event_manager != null and event_manager.has_method("bind_runtime"):
		event_manager.call("bind_runtime", null, null)

	var market_manager: Node = get_node_or_null("/root/MarketManager")
	_call_if_available(market_manager, &"reset_for_new_game")

	var achievement_manager: Node = get_node_or_null("/root/AchievementManager")
	if achievement_manager != null:
		if achievement_manager.has_method("reset_session"):
			achievement_manager.call("reset_session")
		elif achievement_manager.has_method("reset_for_new_game"):
			var no_players: Array[PlayerClass] = []
			achievement_manager.call("reset_for_new_game", no_players)

	var food_manager: Node = get_node_or_null("/root/FoodManager")
	_call_if_available(food_manager, &"reset_session")

	player_data.clear()
	_active_session_setup = null
	_local_session_prepared = false

## 正式结算界面的“返回主菜单”入口。
func return_to_main_menu(scene_path: String = MAIN_MENU_SCENE) -> Error:
	reset_session()
	if get_tree() == null:
		return ERR_UNCONFIGURED
	return get_tree().change_scene_to_file(scene_path)

func _call_if_available(target: Node, method_name: StringName, arguments: Array = []) -> void:
	if target != null and target.has_method(method_name):
		target.callv(method_name, arguments)

func _clear_property_if_available(target: Node, property_name: StringName) -> void:
	if target == null:
		return
	for property_info: Dictionary in target.get_property_list():
		if StringName(property_info.get("name", "")) == property_name:
			target.set(property_name, null)
			return
