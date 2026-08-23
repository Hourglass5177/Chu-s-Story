extends Node

const MAIN_MENU_SCENE: String = "res://main_menu.tscn"

var player_data: Array = []

## 清理上一局的全部运行时绑定。每个管理器都通过能力检查调用，便于系统分阶段接入。
func reset_session() -> void:
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = false

	var turn_manager: Node = get_node_or_null("/root/TurnManager")
	_call_if_available(turn_manager, &"reset_session")

	var resource_manager: Node = get_node_or_null("/root/ResourceManager")
	_call_if_available(resource_manager, &"reset_for_new_game")
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

	player_data.clear()

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
