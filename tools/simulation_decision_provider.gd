extends RefCounted
class_name SimulationDecisionProvider

enum Strategy { LEGAL_RANDOM, BALANCED_GREEDY }

var strategy: Strategy = Strategy.LEGAL_RANDOM

func _init(p_strategy: Strategy = Strategy.LEGAL_RANDOM) -> void:
	strategy = p_strategy

func decide(ticket: InteractionTicket):
	var request = ticket.metadata.get("request")
	if request is EventChoiceRequest:
		return _decide_event_request(request)
	if request is ProfessionDrawRequest:
		return _decide_draw_request(request)
	if request is ProfessionSectionChoiceRequest:
		if request.optional and strategy == Strategy.LEGAL_RANDOM and GameManager.randi_between(0, 3) == 0:
			return null
		return _pick(request.options)
	return ticket.timeout_resolver.call(ticket) if ticket.timeout_resolver.is_valid() else null

func _decide_event_request(request: EventChoiceRequest):
	if request.options.is_empty():
		return [] if request.multiple else null
	if request.multiple:
		if request.optional and strategy == Strategy.LEGAL_RANDOM and GameManager.randi_between(0, 3) == 0:
			return []
		var wanted: int = request.min_selections if request.min_selections > 0 else request.max_selections
		return request.options.slice(0, mini(wanted, request.options.size()))
	if request.optional and strategy == Strategy.LEGAL_RANDOM and GameManager.randi_between(0, 3) == 0:
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
		return GameManager.pick_from(options)
	return options[0]
