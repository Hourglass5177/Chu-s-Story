extends RefCounted
class_name SimulationMatchConfig

var player_count: int
var strategy: SimulationDecisionProvider.Strategy
var match_index: int
var base_seed: int
var world_seed: int
var decision_seed: int
var target_score: int = SessionSetup.DEFAULT_TARGET_SCORE:
	set(value):
		target_score = normalize_target_score(value)
var locations: Array[String] = []
var professions: Array[String] = []

func _init(
		p_player_count: int = 2,
		p_strategy: SimulationDecisionProvider.Strategy = SimulationDecisionProvider.Strategy.LEGAL_RANDOM,
		p_match_index: int = 0,
		p_base_seed: int = 20260824
) -> void:
	player_count = p_player_count
	strategy = p_strategy
	match_index = p_match_index
	base_seed = p_base_seed
	world_seed = base_seed + player_count * 1_000_000 + match_index
	decision_seed = world_seed + (int(strategy) + 1) * 100_000_000

func to_dictionary() -> Dictionary:
	return {
		"player_count": player_count,
		"strategy": SimulationDecisionProvider.strategy_name(strategy),
		"match_index": match_index,
		"base_seed": base_seed,
		"world_seed": world_seed,
		"decision_seed": decision_seed,
		"target_score": target_score,
		"locations": locations.duplicate(),
		"professions": professions.duplicate(),
	}

static func from_dictionary(data: Dictionary) -> SimulationMatchConfig:
	var config := SimulationMatchConfig.new(
		int(data.get("player_count", 2)),
		SimulationDecisionProvider.parse_strategy(String(data.get("strategy", "legal_random"))),
		int(data.get("match_index", 0)),
		int(data.get("base_seed", 20260824))
	)
	config.world_seed = int(data.get("world_seed", config.world_seed))
	config.decision_seed = int(data.get("decision_seed", config.decision_seed))
	config.target_score = int(data.get("target_score", SessionSetup.DEFAULT_TARGET_SCORE))
	config.locations.assign(data.get("locations", []))
	config.professions.assign(data.get("professions", []))
	return config

static func normalize_target_score(value: int) -> int:
	return value if SessionSetup.TARGET_SCORE_OPTIONS.has(value) else SessionSetup.DEFAULT_TARGET_SCORE
