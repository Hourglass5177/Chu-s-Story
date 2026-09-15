class_name FoodShopVisit
extends RefCounted

var player: PlayerClass
var shelf: Array[食物牌] = []
var refreshed: bool = false
var closed: bool = true
var session: int = -1
var epoch: int = -1

func begin(owner_player: PlayerClass) -> bool:
	if not closed or owner_player == null:
		return false
	if TurnManager.players.has(owner_player):
		if not owner_player.alive or not owner_player.can_execute_tile_action() or owner_player.map.grid_map[owner_player.now_pos].type != MapSection.SectionType.商店: return false
	player = owner_player
	session = TurnManager.get_session_generation()
	epoch = TurnManager.get_turn_epoch()
	closed = false
	refreshed = false
	shelf = ResourceManager.draw_shop_foods(3)
	player.last_opened_shop_arrival_id = player.arrival_id
	return true

func is_current() -> bool:
	return not closed and is_instance_valid(player) and (not TurnManager.players.has(player) or (player.onTurn and TurnManager.now_phase == TurnManager.TurnPhase.ACTION)) and session == TurnManager.get_session_generation() and epoch == TurnManager.get_turn_epoch()

func can_refresh() -> bool:
	return is_current() and not refreshed and ProfessionManager.get_food_shop_refresh_limit(player) > 0 and not ResourceManager.食物牌库.is_empty()

func refresh() -> bool:
	if not can_refresh():
		return false
	refreshed = true
	var old := shelf.duplicate()
	shelf = ResourceManager.draw_shop_foods(3)
	ResourceManager.return_shop_foods_to_bottom(old)
	ProfessionManager.notify_skill_triggered(player, "刷新商店")
	return true

func buy(card: 食物牌) -> bool:
	if not is_current() or not shelf.has(card) or not ResourceManager.buy_food(player, card):
		return false
	shelf.erase(card)
	return true

func close() -> void:
	if closed:
		return
	# A stale visit must not return old cards into a newly shuffled session.
	if session == TurnManager.get_session_generation():
		ResourceManager.return_shop_foods_to_bottom(shelf)
	shelf.clear()
	closed = true
	player = null
