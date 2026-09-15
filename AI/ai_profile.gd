class_name AIProfile
extends Resource

const LABELS: Array[String] = ["简单", "普通", "困难"]
const DESCRIPTIONS: Array[String] = ["偏重眼前收益，电脑传承成功率60%。", "兼顾资源与组合，电脑传承成功率80%。", "更重视长期目标与对手威胁，电脑传承必成功。"]
@export var version: int = 3
@export var difficulty: int = 1
@export var inheritance_chance: float = 0.8
@export var planning_depth: int = 3
@export var beam_width: int = 8
@export var node_budget: int = 2048
@export var goal_horizon: int = 2
@export var frame_budget_usec: int = 2000
@export var score_weight: float = 100.0
@export var money_weight: float = 0.025
@export var energy_weight: float = 7.0
@export var unsafe_penalty: float = 2000.0
@export var decision_seed: int = 1

static func is_valid(value: int) -> bool:
	return value >= 0 and value < LABELS.size()

static func for_difficulty(value: int) -> AIProfile:
	assert(is_valid(value), "Invalid AI difficulty")
	var result := AIProfile.new()
	result.difficulty = value
	result.inheritance_chance = [0.6, 0.8, 1.0][value]
	result.planning_depth = [2, 3, 5][value]
	result.beam_width = [4, 8, 24][value]
	result.node_budget = [512, 2048, 8192][value]
	result.goal_horizon = [0, 2, 4][value]
	return result

func parameters() -> Dictionary:
	return {"version": version, "difficulty": difficulty, "inheritance_chance": inheritance_chance,
		"planning_depth": planning_depth, "beam_width": beam_width, "node_budget": node_budget,
		"goal_horizon": goal_horizon, "frame_budget_usec": frame_budget_usec,
		"score_weight": score_weight, "money_weight": money_weight,
		"energy_weight": energy_weight, "unsafe_penalty": unsafe_penalty, "decision_seed": decision_seed}
