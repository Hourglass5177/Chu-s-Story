extends Node

signal discovery_recorded(kind: StringName, entry_id: StringName)
signal discovery_progress_changed(kind: StringName, discovered: int, total: int)

const SAVE_VERSION: int = 1
const DEFAULT_STORAGE_PATH: String = "user://discovery.cfg"

const KIND_FEIYI := &"feiyi"
const KIND_FOOD := &"food"
const KIND_EVENT := &"event"
const KIND_ACHIEVEMENT := &"achievement"
const KIND_PROFESSION := &"profession"
const KIND_SCENERY := &"scenery"
const KIND_MINIGAME := &"minigame"

const ALL_KINDS: Array[StringName] = [
	KIND_FEIYI,
	KIND_FOOD,
	KIND_EVENT,
	KIND_ACHIEVEMENT,
	KIND_PROFESSION,
	KIND_SCENERY,
	KIND_MINIGAME,
]
const PUBLIC_KINDS: Array[StringName] = [KIND_FEIYI, KIND_PROFESSION, KIND_SCENERY]
const RESOURCE_ROOTS: Dictionary = {
	KIND_FEIYI: "res://Cards/非遗牌",
	KIND_FOOD: "res://Cards/食物牌",
	KIND_EVENT: "res://Cards/事件牌",
	KIND_ACHIEVEMENT: "res://Cards/成就牌",
	KIND_MINIGAME: "res://InheritanceTasks/Definitions",
}

var _storage_path: String = DEFAULT_STORAGE_PATH
var _discovered: Dictionary = {}
var _known_ids: Dictionary = {}
var _loaded: bool = false
var _test_storage_enabled: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_initialize_sets()
	load_progress()
	# DiscoveryManager 位于事件与成就 Autoload 之后，可在首帧前直接连接，
	# 避免启动同一帧公开内容时漏记发现。
	_connect_sources()


func is_discovered(kind: StringName, entry_id: StringName) -> bool:
	if not _is_known(kind, entry_id):
		return false
	return PUBLIC_KINDS.has(kind) or (_discovered.get(kind, {}) as Dictionary).has(entry_id)


func record_discovery(kind: StringName, entry_id: StringName) -> bool:
	if PUBLIC_KINDS.has(kind) or not _is_known(kind, entry_id):
		return false
	var entries: Dictionary = _discovered[kind]
	if entries.has(entry_id):
		return false
	entries[entry_id] = true
	if _should_persist():
		save_progress()
	var progress := get_discovery_progress(kind)
	discovery_recorded.emit(kind, entry_id)
	discovery_progress_changed.emit(kind, int(progress.discovered), int(progress.total))
	return true


func record_food_face_presented(card: 食物牌) -> bool:
	return card != null and record_discovery(KIND_FOOD, card.food_id)


func get_discovery_progress(kind: StringName) -> Dictionary:
	var known := get_known_ids(kind)
	var discovered_count := known.size() if PUBLIC_KINDS.has(kind) else 0
	if not PUBLIC_KINDS.has(kind):
		for entry_id: StringName in known:
			if (_discovered.get(kind, {}) as Dictionary).has(entry_id):
				discovered_count += 1
	return {"discovered": discovered_count, "total": known.size()}


func get_known_ids(kind: StringName) -> Array[StringName]:
	if not ALL_KINDS.has(kind):
		return []
	if not _known_ids.has(kind):
		_known_ids[kind] = _scan_known_ids(kind)
	var result: Array[StringName] = []
	result.assign((_known_ids[kind] as Array).duplicate())
	return result


func configure_storage_path(path: String, load_now: bool = true) -> void:
	_storage_path = path if not path.is_empty() else DEFAULT_STORAGE_PATH
	_test_storage_enabled = _storage_path != DEFAULT_STORAGE_PATH
	_discovered.clear()
	_initialize_sets()
	_loaded = false
	if load_now:
		load_progress()


func load_progress() -> Error:
	_initialize_sets()
	for kind: StringName in ALL_KINDS:
		(_discovered[kind] as Dictionary).clear()
	var config := ConfigFile.new()
	var error := config.load(_storage_path)
	if error == ERR_FILE_NOT_FOUND:
		_loaded = true
		return OK
	if error != OK or int(config.get_value("meta", "version", -1)) != SAVE_VERSION:
		_loaded = true
		return error if error != OK else ERR_INVALID_DATA
	for kind: StringName in ALL_KINDS:
		if PUBLIC_KINDS.has(kind):
			continue
		var values: Variant = config.get_value("discoveries", String(kind), [])
		for value: Variant in values:
			var entry_id := StringName(str(value))
			if _is_known(kind, entry_id):
				(_discovered[kind] as Dictionary)[entry_id] = true
	_loaded = true
	return OK


func save_progress() -> Error:
	var config := ConfigFile.new()
	config.set_value("meta", "version", SAVE_VERSION)
	for kind: StringName in ALL_KINDS:
		if PUBLIC_KINDS.has(kind):
			continue
		var values: Array[String] = []
		for entry_id: StringName in (_discovered[kind] as Dictionary).keys():
			values.append(String(entry_id))
		values.sort()
		config.set_value("discoveries", String(kind), PackedStringArray(values))
	return config.save(_storage_path)


func clear_runtime_cache() -> void:
	_known_ids.clear()


func _connect_sources() -> void:
	if EventManager != null and not EventManager.event_revealed.is_connected(_on_event_revealed):
		EventManager.event_revealed.connect(_on_event_revealed)
	if AchievementManager != null and not AchievementManager.achievement_claimed.is_connected(_on_achievement_claimed):
		AchievementManager.achievement_claimed.connect(_on_achievement_claimed)


func _on_event_revealed(_player: PlayerClass, card: 事件牌) -> void:
	if card != null:
		record_discovery(KIND_EVENT, card.event_id)


func _on_achievement_claimed(_player: PlayerClass, card: 成就牌) -> void:
	if card != null:
		record_discovery(KIND_ACHIEVEMENT, card.achievement_id)


func _initialize_sets() -> void:
	for kind: StringName in ALL_KINDS:
		if not _discovered.has(kind):
			_discovered[kind] = {}


func _is_known(kind: StringName, entry_id: StringName) -> bool:
	return not entry_id.is_empty() and get_known_ids(kind).has(entry_id)


func _scan_known_ids(kind: StringName) -> Array[StringName]:
	if kind == KIND_PROFESSION:
		var profession_ids: Array[StringName] = []
		for definition: ProfessionDefinition in ProfessionManager.get_all_definitions():
			if definition != null and not definition.profession_id.is_empty():
				profession_ids.append(definition.profession_id)
		profession_ids.sort()
		return profession_ids
	if kind == KIND_SCENERY:
		return _scan_scenery_ids()
	var paths: Array[String] = []
	_collect_resource_paths(String(RESOURCE_ROOTS.get(kind, "")), paths)
	var ids: Array[StringName] = []
	for path: String in paths:
		var resource := ResourceLoader.load(path)
		var entry_id := _resource_entry_id(kind, resource, path)
		if not entry_id.is_empty() and not ids.has(entry_id):
			ids.append(entry_id)
	if PUBLIC_KINDS.has(kind):
		ids.sort()
	else:
		# 隐藏条目使用与名称无关的固定槽位顺序。玩家逐张翻开后也无法
		# 根据拼音 ID 的相邻位置推断尚未发现的牌名。
		ids.sort_custom(func(first: StringName, second: StringName) -> bool:
			var first_key := _opaque_slot_key(kind, first)
			var second_key := _opaque_slot_key(kind, second)
			return first_key < second_key if first_key != second_key else String(first) < String(second)
		)
	return ids


func _opaque_slot_key(kind: StringName, entry_id: StringName) -> String:
	return ("chuwuzhi-discovery-v1|%s|%s" % [kind, entry_id]).sha256_text()


func _resource_entry_id(kind: StringName, resource: Resource, path: String) -> StringName:
	if kind == KIND_FEIYI and resource is 非遗牌:
		return StringName(path)
	if kind == KIND_FOOD and resource is 食物牌:
		return (resource as 食物牌).food_id
	if kind == KIND_EVENT and resource is 事件牌:
		return (resource as 事件牌).event_id
	if kind == KIND_ACHIEVEMENT and resource is 成就牌:
		return (resource as 成就牌).achievement_id
	if kind == KIND_MINIGAME and resource is HeritageTaskDefinition:
		# 传承小游戏使用 Definition 内显式声明的稳定 ID。不要把资源路径写进
		# 永久存档，否则策划整理文件名或目录时会让玩家丢失解锁记录。
		return (resource as HeritageTaskDefinition).task_id
	return &""


func _collect_resource_paths(root_path: String, output: Array[String]) -> void:
	if root_path.is_empty():
		return
	var directory := DirAccess.open(root_path)
	if directory == null:
		return
	for child_dir: String in directory.get_directories():
		_collect_resource_paths(root_path.path_join(child_dir), output)
	for file_name: String in directory.get_files():
		if not file_name.ends_with(".tres") and not file_name.ends_with(".tres.remap"):
			continue
		output.append(root_path.path_join(file_name.trim_suffix(".remap")))
	output.sort()


func _scan_scenery_ids() -> Array[StringName]:
	var packed := load("res://地图/map.tscn") as PackedScene
	if packed == null:
		return []
	var root := packed.instantiate()
	var ids: Array[StringName] = []
	_collect_scenery_ids(root, ids)
	root.free()
	ids.sort()
	return ids


func _collect_scenery_ids(node: Node, output: Array[StringName]) -> void:
	if node is MapSection:
		var section := node as MapSection
		if section.type == MapSection.SectionType.风景:
			var entry_id := StringName("%d,%d,%d" % [section.location_index.x, section.location_index.y, section.location_index.z])
			if not output.has(entry_id):
				output.append(entry_id)
	for child: Node in node.get_children():
		_collect_scenery_ids(child, output)


func _should_persist() -> bool:
	if _test_storage_enabled:
		return true
	if GameManager.is_headless_simulation():
		return false
	for argument: String in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if "gut_cmdln.gd" in argument or argument.begins_with("-g"):
			return false
	return true
