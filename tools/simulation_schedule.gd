extends RefCounted
class_name SimulationSchedule

const LOCATION_NAMES: Array[String] = ["十堰", "随州", "孝感", "黄冈", "荆州", "恩施"]
const PROFESSION_NAMES: Array[String] = ["美食博主", "魔术博主", "探险博主", "商业博主", "旅行博主", "生活博主"]
const REGION_BASES: Array[Array] = [
	[0, 1, 2, 3, 4, 5],
	[0, 2, 4, 1, 3, 5],
	[0, 5, 3, 1, 4, 2],
]
const PROFESSION_BASES: Array[Array] = [
	[0, 2, 4, 1, 5, 3],
	[0, 3, 1, 5, 2, 4],
	[0, 4, 5, 2, 1, 3],
]

static func build_match(
		player_count: int,
		strategy: SimulationDecisionProvider.Strategy,
		match_index: int,
		base_seed: int = 20260824
) -> SimulationMatchConfig:
	var config := SimulationMatchConfig.new(player_count, strategy, match_index, base_seed)
	var repeat_index := posmod(floori(float(match_index) / 36.0), REGION_BASES.size())
	var region_offset := posmod(match_index, 6)
	var profession_offset := posmod(floori(float(match_index) / 6.0), 6)
	var region_base: Array = REGION_BASES[repeat_index]
	var profession_base: Array = PROFESSION_BASES[repeat_index]
	for seat: int in player_count:
		config.locations.append(LOCATION_NAMES[posmod(int(region_base[seat]) + region_offset, 6)])
		config.professions.append(PROFESSION_NAMES[posmod(int(profession_base[seat]) + profession_offset, 6)])
	return config

static func build_standard(base_seed: int = 20260824, matches_per_group: int = 108) -> Array[SimulationMatchConfig]:
	var result: Array[SimulationMatchConfig] = []
	for player_count: int in [2, 3, 6]:
		for strategy: SimulationDecisionProvider.Strategy in SimulationDecisionProvider.all_strategies():
			for match_index: int in matches_per_group:
				result.append(build_match(player_count, strategy, match_index, base_seed))
	return result
