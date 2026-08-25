extends RefCounted
class_name BalanceReportBuilder

const BOOTSTRAP_SAMPLES := 2000
const BOOTSTRAP_SEED := 20260825
const REGION_NAMES: Array[String] = ["十堰", "随州", "孝感", "黄冈", "荆州", "恩施"]

static func build_markdown(reports: Array[Dictionary]) -> String:
	var aborted_count := 0
	for report: Dictionary in reports:
		if bool(report.get("aborted", false)):
			aborted_count += 1
	var lines: Array[String] = [
		"# Beta 0.2.1 平衡模拟报告", "",
		"- 对局数：%d" % reports.size(),
		"- 异常终止：%d" % aborted_count,
		"- Bootstrap：以对局为重采样单位，固定 %d 次" % BOOTSTRAP_SAMPLES,
		"", "## 对局构成", "",
		"| 人数 | 策略 | 对局 | 平均回合 |", "|---:|---|---:|---:|",
	]
	for group: Dictionary in _match_groups(reports):
		lines.append("| %d | %s | %d | %.2f |" % [group.player_count, group.strategy, group.count, group.turn_mean])
	lines.append_array([
		"", "## 职业基线", "",
		"| 初始职业 | 样本 | 平均名次 | 平均分 | 中心化分差 | 95% CI | 冠军权重 |", "|---|---:|---:|---:|---:|---:|---:|",
	])
	var profession_names := _profession_names(reports)
	for profession_name: String in profession_names:
		var stats := _profession_stats(reports, profession_name)
		var score_ci := bootstrap_ci(reports, profession_name, &"centered_score")
		lines.append("| %s | %d | %.2f | %.2f | %.2f | %.2f–%.2f | %.1f%% |" % [
			profession_name, stats.count, stats.rank_mean, stats.score_mean, stats.centered_score_mean,
			score_ci.x, score_ci.y, stats.champion_credit_mean * 100.0,
		])
	lines.append_array(["", "## 座位差异", "", "| 座位 | 样本 | 平均名次 | 平均分 | 中心化分差 | 冠军权重 |", "|---:|---:|---:|---:|---:|---:|"])
	for seat: int in 6:
		var seat_stats := _seat_stats(reports, seat)
		if seat_stats.count <= 0:
			continue
		lines.append("| %d | %d | %.2f | %.2f | %.2f | %.1f%% |" % [
			seat + 1, seat_stats.count, seat_stats.rank_mean, seat_stats.score_mean,
			seat_stats.centered_score_mean, seat_stats.champion_credit_mean * 100.0,
		])
	lines.append_array(["", "## 起始地区基线", "", "| 地区 | 样本 | 平均名次 | 平均分 | 冠军权重 |", "|---|---:|---:|---:|---:|"])
	for region: String in REGION_NAMES:
		var region_stats := _region_stats(reports, region)
		lines.append("| %s | %d | %.2f | %.2f | %.1f%% |" % [
			region, region_stats.count, region_stats.rank_mean, region_stats.score_mean,
			region_stats.champion_credit_mean * 100.0,
		])
	lines.append_array(["", "## 自动标记", ""])
	var flags := build_flags(reports)
	if flags.is_empty():
		lines.append("- 当前样本未触发预设异常阈值。")
	else:
		for flag: String in flags:
			lines.append("- %s" % flag)
	lines.append_array(["", "本报告只记录现状与可疑趋势，不自动修改玩法数值。", ""])
	return "\n".join(lines)

static func _match_groups(reports: Array[Dictionary]) -> Array[Dictionary]:
	var buckets := {}
	for report: Dictionary in reports:
		var key := "%d|%s" % [int(report.get("player_count", 0)), String(report.get("strategy", "unknown"))]
		var bucket: Dictionary = buckets.get(key, {
			"player_count": int(report.get("player_count", 0)),
			"strategy": String(report.get("strategy", "unknown")),
			"count": 0,
			"turn_sum": 0.0,
		})
		bucket.count += 1
		bucket.turn_sum += float(report.get("turns", 0))
		buckets[key] = bucket
	var result: Array[Dictionary] = []
	for key in buckets:
		var bucket: Dictionary = buckets[key]
		bucket["turn_mean"] = bucket.turn_sum / maxf(bucket.count, 1)
		result.append(bucket)
	result.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		if first.player_count != second.player_count:
			return first.player_count < second.player_count
		return first.strategy < second.strategy
	)
	return result

static func bootstrap_ci(reports: Array[Dictionary], profession_name: String, metric: StringName) -> Vector2:
	if reports.is_empty():
		return Vector2.ZERO
	var rng := RandomNumberGenerator.new()
	rng.seed = BOOTSTRAP_SEED + profession_name.hash() + String(metric).hash()
	var estimates: Array[float] = []
	for _sample: int in BOOTSTRAP_SAMPLES:
		var sampled: Array[Dictionary] = []
		for _index: int in reports.size():
			sampled.append(reports[rng.randi_range(0, reports.size() - 1)])
		var stats := _profession_stats(sampled, profession_name)
		estimates.append(float(stats.get(String(metric) + "_mean", 0.0)))
	estimates.sort()
	return Vector2(estimates[49], estimates[1949])

static func build_flags(reports: Array[Dictionary]) -> Array[String]:
	var flags: Array[String] = []
	for profession_name: String in _profession_names(reports):
		var stats := _profession_stats(reports, profession_name)
		var score_ci := bootstrap_ci(reports, profession_name, &"centered_score")
		if absf(stats.centered_score_mean) >= 1.0 and (score_ci.x > 0.0 or score_ci.y < 0.0):
			flags.append("【%s】中心化分差 %.2f，且置信区间不含 0。" % [profession_name, stats.centered_score_mean])
		var champion_ci := bootstrap_ci(reports, profession_name, &"champion_credit")
		var overall_credit := _overall_champion_credit(reports)
		if absf(stats.champion_credit_mean - overall_credit) >= 0.10 \
				and (champion_ci.x > overall_credit or champion_ci.y < overall_credit):
			flags.append("【%s】冠军权重与总体相差至少 10 个百分点。" % profession_name)
	var end_counts := {}
	for report: Dictionary in reports:
		var key := int(report.get("end_reason", -1))
		end_counts[key] = int(end_counts.get(key, 0)) + 1
	for key in end_counts:
		if float(end_counts[key]) / maxf(reports.size(), 1) > 0.8:
			flags.append("结束原因 %s 占比超过 80%%。" % key)
	var event_counts := {}
	for report: Dictionary in reports:
		for key in (report.get("events", {}) as Dictionary):
			var event_id := String(key).trim_suffix(":no_effect")
			var counts: Dictionary = event_counts.get(event_id, {"total": 0, "no_effect": 0})
			if String(key).ends_with(":no_effect"):
				counts.no_effect += int(report.events[key])
			else:
				counts.total += int(report.events[key])
			event_counts[event_id] = counts
	for event_id in event_counts:
		var counts: Dictionary = event_counts[event_id]
		if counts.total >= 20 and float(counts.no_effect) / counts.total > 0.4:
			flags.append("事件【%s】无事发生率超过 40%%（样本 %d）。" % [event_id, counts.total])
	return flags

static func _profession_names(reports: Array[Dictionary]) -> Array[String]:
	var names := {}
	for report: Dictionary in reports:
		for player: Dictionary in report.get("players", []):
			names[String(player.get("initial_profession", player.get("profession", "未知")))] = true
	var result: Array[String] = []
	result.assign(names.keys())
	result.sort()
	return result

static func _profession_stats(reports: Array[Dictionary], profession_name: String) -> Dictionary:
	var count := 0
	var rank_sum := 0.0
	var score_sum := 0.0
	var centered_sum := 0.0
	var champion_sum := 0.0
	for report: Dictionary in reports:
		var players: Array = report.get("players", [])
		var match_score_mean := 0.0
		for player: Dictionary in players:
			match_score_mean += float(player.get("score", 0))
		match_score_mean /= maxf(players.size(), 1)
		var winners: Array = report.get("winners", [])
		var winner_indexes := {}
		for winner in winners:
			winner_indexes[int(winner)] = true
		var winner_credit := 1.0 / maxf(winners.size(), 1)
		for player: Dictionary in players:
			if String(player.get("initial_profession", player.get("profession", "未知"))) != profession_name:
				continue
			count += 1
			rank_sum += float(player.get("rank", 0))
			score_sum += float(player.get("score", 0))
			centered_sum += float(player.get("score", 0)) - match_score_mean
			if winner_indexes.has(int(player.get("player_index", -1))):
				champion_sum += winner_credit
	return {
		"count": count,
		"rank_mean": rank_sum / maxf(count, 1),
		"score_mean": score_sum / maxf(count, 1),
		"centered_score_mean": centered_sum / maxf(count, 1),
		"champion_credit_mean": champion_sum / maxf(count, 1),
	}

static func _seat_stats(reports: Array[Dictionary], seat: int) -> Dictionary:
	return _grouped_player_stats(reports, func(_report: Dictionary, player: Dictionary) -> bool:
		return int(player.get("player_index", -1)) == seat
	)

static func _region_stats(reports: Array[Dictionary], region: String) -> Dictionary:
	return _grouped_player_stats(reports, func(report: Dictionary, player: Dictionary) -> bool:
		var config: Dictionary = report.get("match_config", {})
		var locations: Array = config.get("locations", [])
		var seat := int(player.get("player_index", -1))
		return seat >= 0 and seat < locations.size() and String(locations[seat]) == region
	)

static func _grouped_player_stats(reports: Array[Dictionary], predicate: Callable) -> Dictionary:
	var count := 0
	var rank_sum := 0.0
	var score_sum := 0.0
	var centered_sum := 0.0
	var champion_sum := 0.0
	for report: Dictionary in reports:
		var players: Array = report.get("players", [])
		var score_mean := 0.0
		for player: Dictionary in players:
			score_mean += float(player.get("score", 0))
		score_mean /= maxf(players.size(), 1)
		var winner_indexes := {}
		var winners: Array = report.get("winners", [])
		for winner in winners:
			winner_indexes[int(winner)] = true
		var winner_credit := 1.0 / maxf(winners.size(), 1)
		for player: Dictionary in players:
			if not predicate.call(report, player):
				continue
			count += 1
			rank_sum += float(player.get("rank", 0))
			score_sum += float(player.get("score", 0))
			centered_sum += float(player.get("score", 0)) - score_mean
			if winner_indexes.has(int(player.get("player_index", -1))):
				champion_sum += winner_credit
	return {
		"count": count,
		"rank_mean": rank_sum / maxf(count, 1),
		"score_mean": score_sum / maxf(count, 1),
		"centered_score_mean": centered_sum / maxf(count, 1),
		"champion_credit_mean": champion_sum / maxf(count, 1),
	}

static func _overall_champion_credit(reports: Array[Dictionary]) -> float:
	var players := 0
	var credit := 0.0
	for report: Dictionary in reports:
		var winner_count: int = (report.get("winners", []) as Array).size()
		players += (report.get("players", []) as Array).size()
		credit += 1.0 if winner_count > 0 else 0.0
	return credit / maxf(players, 1)
