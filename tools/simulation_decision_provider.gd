extends RefCounted
class_name SimulationDecisionProvider

enum Strategy { LEGAL_RANDOM, SURVIVAL_GREEDY, SCORE_GREEDY }

var strategy: Strategy = Strategy.LEGAL_RANDOM
var _rng := RandomNumberGenerator.new()

func _init(p_strategy: Strategy = Strategy.LEGAL_RANDOM, decision_seed: int = 0) -> void:
	strategy = p_strategy
	_rng.seed = decision_seed

static func all_strategies() -> Array[Strategy]:
	return [Strategy.LEGAL_RANDOM, Strategy.SURVIVAL_GREEDY, Strategy.SCORE_GREEDY]

static func strategy_name(value: Strategy) -> StringName:
	match value:
		Strategy.SURVIVAL_GREEDY:
			return &"survival_greedy"
		Strategy.SCORE_GREEDY:
			return &"score_greedy"
		_:
			return &"legal_random"

static func parse_strategy(value: String) -> Strategy:
	match value:
		"survival_greedy", "balanced_greedy":
			return Strategy.SURVIVAL_GREEDY
		"score_greedy":
			return Strategy.SCORE_GREEDY
		_:
			return Strategy.LEGAL_RANDOM

func decide(ticket: InteractionTicket):
	var request = ticket.metadata.get("request")
	if request is EventChoiceRequest:
		return _decide_event_request(request)
	if request is ProfessionDrawRequest:
		return _decide_draw_request(request)
	if request is ProfessionSectionChoiceRequest:
		if request.optional and strategy == Strategy.LEGAL_RANDOM and _rng.randi_range(0, 3) == 0:
			return null
		return _pick(request.options)
	return ticket.timeout_resolver.call(ticket) if ticket.timeout_resolver.is_valid() else null

func _decide_event_request(request: EventChoiceRequest):
	if request.options.is_empty():
		return [] if request.multiple else null
	if request.multiple:
		if request.optional and strategy == Strategy.LEGAL_RANDOM and _rng.randi_range(0, 3) == 0:
			return []
		var wanted: int = request.min_selections if request.min_selections > 0 else request.max_selections
		return request.options.slice(0, mini(wanted, request.options.size()))
	if request.optional and strategy == Strategy.LEGAL_RANDOM and _rng.randi_range(0, 3) == 0:
		return null
	return _pick(request.options)

func _decide_draw_request(request: ProfessionDrawRequest) -> ProfessionDrawResult:
	if request.cards.is_empty():
		return ProfessionDrawResult.new(null, [], true)
	var selected = _pick(request.cards)
	var return_order: Array = request.cards.duplicate()
	return_order.erase(selected)
	return ProfessionDrawResult.new(selected, return_order)

func _pick(options: Array):
	if options.is_empty():
		return null
	if strategy == Strategy.LEGAL_RANDOM:
		return options[_rng.randi_range(0, options.size() - 1)]
	return options[0]

func pick_action(candidates: Array[SimulationActionCandidate], _observation: SimulationObservation = null) -> SimulationActionCandidate:
	var legal: Array[SimulationActionCandidate] = candidates.filter(func(candidate): return candidate != null and candidate.legal)
	if legal.is_empty():
		return null
	if strategy == Strategy.LEGAL_RANDOM:
		return legal[_rng.randi_range(0, legal.size() - 1)]
	var best := legal[0]
	for candidate: SimulationActionCandidate in legal:
		if candidate.utility > best.utility:
			best = candidate
	return best

func pick_value(options: Array):
	return _pick(options)
