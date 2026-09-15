class_name ComputerInheritanceService
extends RefCounted

var rng := RandomNumberGenerator.new()
var results: Dictionary = {}

func configure(seed_value: int) -> void:
	rng.seed = seed_value
	results.clear()

static func succeeds(sample: float, chance: float = 0.8) -> bool:
	return sample >= 0.0 and sample <= 1.0 and (chance >= 1.0 or sample < chance)

func sample_attempt(attempt: HeritageTaskAttempt, profile: AIProfile = null) -> HeritageTaskResult:
	if attempt == null or not attempt.energy_paid or not is_instance_valid(attempt.player) or not attempt.player.is_bot:
		return null
	var key := "%d:%d" % [attempt.session_generation, attempt.attempt_id]
	if not results.has(key):
		var chance := profile.inheritance_chance if profile != null else AIProfile.for_difficulty(attempt.player.ai_difficulty).inheritance_chance
		results[key] = HeritageTaskResult.success(attempt.task_id, {}, "电脑自动传承：成功") if succeeds(rng.randf(), chance) else HeritageTaskResult.failure(attempt.task_id, &"computer_attempt_failed", "电脑自动传承：失败")
	return results[key]
