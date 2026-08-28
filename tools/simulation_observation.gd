extends RefCounted
class_name SimulationObservation

var player_index: int = -1
var phase: int = -1
var turn_number: int = 0
var energy: int = 0
var money: int = 0
var score: int = 0
var public_players: Array[Dictionary] = []
var own_food_ids: Array[StringName] = []
var own_event_ids: Array[StringName] = []
var own_feiyi_names: Array[String] = []
var public_market_cards: Array[String] = []

static func capture(player: PlayerClass) -> SimulationObservation:
	var observation := SimulationObservation.new()
	if player == null:
		return observation
	observation.player_index = player.player_index
	observation.phase = int(TurnManager.now_phase)
	observation.turn_number = TurnManager.now_turn
	observation.energy = player.current_energy
	observation.money = player.current_money
	observation.score = player.current_score
	for candidate: PlayerClass in TurnManager.players:
		observation.public_players.append({
			"player_index": candidate.player_index,
			"alive": candidate.alive,
			"energy": candidate.current_energy,
			"money": candidate.current_money,
			"score": candidate.current_score,
			"position": candidate.now_pos,
			"food_count": candidate.食物牌手牌.size(),
			"event_count": candidate.事件牌手牌.size(),
			"feiyi_count": ResourceManager.get_effective_feiyi_cards(candidate).size(),
		})
	for card: 食物牌 in player.食物牌手牌:
		observation.own_food_ids.append(card.food_id)
	for card: 事件牌 in player.事件牌手牌:
		observation.own_event_ids.append(card.event_id)
	for card: 非遗牌 in player.非遗牌手牌:
		observation.own_feiyi_names.append(card.card_name)
	for card: 非遗牌 in MarketManager.get_inventory():
		observation.public_market_cards.append(card.card_name)
	return observation
