extends Node

signal inventory_changed(cards: Array[非遗牌])
signal transaction_completed(player: PlayerClass, card: 非遗牌, transaction_kind: StringName, amount: int)

const MAX_PURCHASES_PER_VISIT: int = 3
const BASE_SELL_PRICE: int = 250
const SCORE_PRICE_STEP: int = 50

var _inventory: Array[非遗牌] = []
var _purchase_counts: Dictionary[PlayerClass, Dictionary] = {}
var _last_visit_arrivals: Dictionary[PlayerClass, int] = {}

func reset_for_new_game() -> void:
	_inventory.clear()
	_purchase_counts.clear()
	_last_visit_arrivals.clear()
	_emit_inventory_changed()

func get_inventory() -> Array[非遗牌]:
	var result: Array[非遗牌] = []
	result.assign(_inventory)
	return result

func is_tradable(card: 非遗牌) -> bool:
	return card != null and card.category != 非遗牌.CardCategory.国家级非遗

func get_sell_price(card: 非遗牌) -> int:
	if not is_tradable(card):
		return 0
	return BASE_SELL_PRICE + maxi(card.base_score, 0) * SCORE_PRICE_STEP

func get_buy_price(card: 非遗牌) -> int:
	return get_sell_price(card) * 2

func get_purchase_count(player: PlayerClass, arrival_id: int) -> int:
	return int(_purchase_counts.get(player, {}).get(arrival_id, 0))

func get_remaining_purchases(player: PlayerClass, arrival_id: int) -> int:
	return maxi(MAX_PURCHASES_PER_VISIT - get_purchase_count(player, arrival_id), 0)

func can_open_visit(player: PlayerClass, arrival_id: int) -> bool:
	return player != null and arrival_id > 0 and int(_last_visit_arrivals.get(player, -1)) != arrival_id

func begin_visit(player: PlayerClass, arrival_id: int) -> bool:
	if not can_open_visit(player, arrival_id):
		return false
	_last_visit_arrivals[player] = arrival_id
	return true

func get_tradable_cards(player: PlayerClass) -> Array[非遗牌]:
	var cards: Array[非遗牌] = []
	if player == null:
		return cards
	for card: 非遗牌 in player.非遗牌手牌:
		if is_tradable(card):
			cards.append(card)
	return cards

func deposit_card(card: 非遗牌, reason: StringName = &"deposit") -> bool:
	if not is_tradable(card) or _inventory.has(card):
		return false
	_inventory.append(card)
	_emit_inventory_changed()
	transaction_completed.emit(null, card, reason, 0)
	return true

func sell_card(player: PlayerClass, card: 非遗牌) -> bool:
	if player == null or not player.非遗牌手牌.has(card) or not is_tradable(card):
		return false
	var price: int = get_sell_price(card)
	if not ResourceManager.remove_feiyi_card(player, card, false):
		return false
	_inventory.append(card)
	ResourceManager.modify_money(player, price, "出售非遗牌")
	ResourceManager.calculate_victory_score(player)
	_refresh_player_ui(player)
	_emit_inventory_changed()
	transaction_completed.emit(player, card, &"sell", price)
	return true

func buy_card(player: PlayerClass, card: 非遗牌, arrival_id: int) -> bool:
	if player == null or not _inventory.has(card) or not is_tradable(card):
		return false
	if get_remaining_purchases(player, arrival_id) <= 0:
		return false
	var price: int = get_buy_price(card)
	if player.current_money < price:
		return false
	_inventory.erase(card)
	if not ResourceManager.add_feiyi_card(player, card, false):
		_inventory.append(card)
		return false
	var player_counts: Dictionary = _purchase_counts.get(player, {})
	player_counts[arrival_id] = int(player_counts.get(arrival_id, 0)) + 1
	_purchase_counts[player] = player_counts
	ResourceManager.modify_money(player, -price, "购买非遗牌", true)
	ResourceManager.calculate_victory_score(player)
	_refresh_player_ui(player)
	_emit_inventory_changed()
	transaction_completed.emit(player, card, &"buy", -price)
	return true

func take_card_free(player: PlayerClass, card: 非遗牌) -> bool:
	if player == null or not _inventory.has(card) or not is_tradable(card):
		return false
	_inventory.erase(card)
	if not ResourceManager.add_feiyi_card(player, card, false):
		_inventory.append(card)
		return false
	ResourceManager.calculate_victory_score(player)
	_refresh_player_ui(player)
	_emit_inventory_changed()
	transaction_completed.emit(player, card, &"free", 0)
	return true

func sample_cards(count: int) -> Array[非遗牌]:
	var candidates: Array[非遗牌] = get_inventory()
	candidates.shuffle()
	var result: Array[非遗牌] = []
	for index: int in mini(maxi(count, 0), candidates.size()):
		result.append(candidates[index])
	return result

func _emit_inventory_changed() -> void:
	inventory_changed.emit(get_inventory())

func _refresh_player_ui(player: PlayerClass) -> void:
	if ResourceManager.hud == null:
		return
	ResourceManager.hud.refresh_feiyi_list(player)
	ResourceManager.hud._update_player_stats(player)
