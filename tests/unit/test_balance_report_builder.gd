extends GutTest

func test_report_builder_uses_fractional_champion_credit_and_is_deterministic() -> void:
	var reports: Array[Dictionary] = [
		_report("美食博主", 10, 1, [0.0, 1.0], 0),
		_report("美食博主", 12, 1, [0], 0),
		_report("旅行博主", 8, 2, [1], 0),
		_report("旅行博主", 9, 2, [1], 0),
	]
	var first := BalanceReportBuilder.build_markdown(reports)
	var second := BalanceReportBuilder.build_markdown(reports)
	assert_eq(first, second)
	assert_string_contains(first, "Bootstrap")
	assert_string_contains(first, "冠军权重")
	assert_string_contains(first, "座位差异")
	assert_string_contains(first, "起始地区基线")

func _report(profession: String, score: int, rank: int, winners: Array, player_index: int) -> Dictionary:
	return {
		"aborted": false,
		"end_reason": 0,
		"winners": winners,
		"events": {},
		"players": [{
			"player_index": player_index,
			"initial_profession": profession,
			"profession": profession,
			"score": score,
			"rank": rank,
		}],
	}
