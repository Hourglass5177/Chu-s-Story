extends Resource
class_name SessionSetup

## 进入正式对局前的本地会话草稿。
## 前端可修改本对象；GameManager 只保存 duplicate_snapshot() 的快照。

enum GameMode { LOCAL, NETWORK, TUTORIAL }

const MIN_PLAYERS: int = 1
const MAX_PLAYERS: int = 6

@export var mode: GameMode = GameMode.LOCAL
@export_range(1, MAX_PLAYERS, 1) var human_count: int = 1
@export_range(0, MAX_PLAYERS - 1, 1) var bot_count: int = 0
@export var players: Array[PlayerSetup] = []


func _init(
		p_mode: GameMode = GameMode.LOCAL,
		p_human_count: int = 1,
		p_bot_count: int = 0
) -> void:
	mode = p_mode
	if _counts_are_valid(p_human_count, p_bot_count):
		_resize_slots_unchecked(p_human_count, p_bot_count)


func resize_slots(new_human_count: int, new_bot_count: int) -> Error:
	if not _counts_are_valid(new_human_count, new_bot_count):
		return ERR_INVALID_PARAMETER
	_resize_slots_unchecked(new_human_count, new_bot_count)
	return OK


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not GameMode.values().has(int(mode)):
		errors.append("游戏模式无效")
	if not _counts_are_valid(human_count, bot_count):
		errors.append("玩家总数须为1至6人，且至少有1名真人玩家")
		return errors
	var expected_count: int = human_count + bot_count
	if players.size() != expected_count:
		errors.append("玩家配置数量与人数不一致")
		return errors

	var used_professions: Dictionary[int, int] = {}
	var used_regions: Dictionary[int, int] = {}
	for index: int in players.size():
		var player: PlayerSetup = players[index]
		var label: String = "P%d" % (index + 1)
		if player == null:
			errors.append("%s配置缺失" % label)
			continue
		if player.slot_index != index:
			errors.append("%s席位编号无效" % label)
		var expected_kind: PlayerSetup.ControlKind = (
			PlayerSetup.ControlKind.HUMAN
			if index < human_count
			else PlayerSetup.ControlKind.BOT
		)
		if player.control_kind != expected_kind:
			errors.append("%s席位类型无效" % label)
		if not player.has_valid_profession():
			errors.append("%s还未选择职业" % label)
		elif used_professions.has(player.profession_type):
			errors.append("%s职业已被P%d选择" % [label, used_professions[player.profession_type] + 1])
		else:
			used_professions[player.profession_type] = index
		if not player.has_valid_starting_region():
			errors.append("%s还未选择出生点" % label)
		elif used_regions.has(player.starting_region):
			errors.append("%s出生点已被P%d选择" % [label, used_regions[player.starting_region] + 1])
		else:
			used_regions[player.starting_region] = index
	return errors


func normalize_display_names() -> void:
	for player: PlayerSetup in players:
		if player != null:
			player.normalize_display_name()


func duplicate_snapshot() -> SessionSetup:
	var snapshot := SessionSetup.new()
	snapshot.mode = mode
	snapshot.human_count = human_count
	snapshot.bot_count = bot_count
	snapshot.players.clear()
	for player: PlayerSetup in players:
		snapshot.players.append(player.duplicate_snapshot() if player != null else null)
	return snapshot


func is_equivalent_to(other: SessionSetup) -> bool:
	if other == null \
			or mode != other.mode \
			or human_count != other.human_count \
			or bot_count != other.bot_count \
			or players.size() != other.players.size():
		return false
	for index: int in players.size():
		var player: PlayerSetup = players[index]
		var other_player: PlayerSetup = other.players[index]
		if player == null or not player.is_equivalent_to(other_player):
			return false
	return true


func to_legacy_player_data() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for player: PlayerSetup in players:
		if player != null:
			result.append(player.to_legacy_dictionary())
	return result


func _resize_slots_unchecked(new_human_count: int, new_bot_count: int) -> void:
	var previous_humans: Array[PlayerSetup] = []
	var previous_bots: Array[PlayerSetup] = []
	for player: PlayerSetup in players:
		if player == null:
			continue
		if player.control_kind == PlayerSetup.ControlKind.BOT:
			previous_bots.append(player)
		else:
			previous_humans.append(player)

	var resized: Array[PlayerSetup] = []
	for human_index: int in new_human_count:
		var human: PlayerSetup
		if human_index < previous_humans.size():
			human = previous_humans[human_index]
		else:
			human = PlayerSetup.new()
		human.slot_index = resized.size()
		human.control_kind = PlayerSetup.ControlKind.HUMAN
		resized.append(human)

	for bot_index: int in new_bot_count:
		var bot: PlayerSetup
		if bot_index < previous_bots.size():
			bot = previous_bots[bot_index]
		else:
			bot = _create_default_bot(bot_index, resized)
		bot.slot_index = resized.size()
		bot.control_kind = PlayerSetup.ControlKind.BOT
		resized.append(bot)

	human_count = new_human_count
	bot_count = new_bot_count
	players.assign(resized)


func _create_default_bot(bot_index: int, configured_players: Array[PlayerSetup]) -> PlayerSetup:
	var bot := PlayerSetup.new(0, PlayerSetup.ControlKind.BOT)
	bot.display_name = "电脑%d" % (bot_index + 1)
	var used_professions: Dictionary[int, bool] = {}
	var used_regions: Dictionary[int, bool] = {}
	for player: PlayerSetup in configured_players:
		if player.has_valid_profession():
			used_professions[player.profession_type] = true
		if player.has_valid_starting_region():
			used_regions[player.starting_region] = true
	for profession: int in PlayerClass.PlayerCharacter.values():
		if not used_professions.has(profession):
			bot.profession_type = profession
			break
	for region_variant: Variant in MapSection.出生点坐标.keys():
		var region: int = int(region_variant)
		if not used_regions.has(region):
			bot.starting_region = region
			break
	return bot


func _counts_are_valid(candidate_humans: int, candidate_bots: int) -> bool:
	var total: int = candidate_humans + candidate_bots
	return candidate_humans >= 1 \
		and candidate_bots >= 0 \
		and total >= MIN_PLAYERS \
		and total <= MAX_PLAYERS
