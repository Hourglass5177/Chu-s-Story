class_name HeritageMinigamePreferences
extends RefCounted

const PATH: String = "user://heritage_minigames.cfg"
static var storage_path: String = PATH
static var _configs: Dictionary = {}
static var disk_read_count: int = 0


static func configure_storage_path(path: String = PATH) -> void:
	storage_path = path if not path.is_empty() else PATH
	_configs.erase(storage_path)

static func reload() -> void:
	_configs.erase(storage_path)

static func _config() -> ConfigFile:
	if not _configs.has(storage_path):
		var config := ConfigFile.new()
		config.load(storage_path)
		disk_read_count += 1
		_configs[storage_path] = config
	return _configs[storage_path] as ConfigFile

static func tutorial_done(id: StringName, version: int) -> bool:
	var config := _config()
	return int(config.get_value("tutorial", str(id), 0)) >= version

static func complete_tutorial(id: StringName, version: int) -> void:
	var config := _config()
	config.set_value("tutorial", str(id), version)
	_save_config(config)

static func offset_ms(device_key: String = "") -> int:
	var config := _config()
	if not device_key.is_empty() and config.has_section_key("audio_device_offsets",device_key):
		return clampi(int(config.get_value("audio_device_offsets",device_key,0)),-300,300)
	return int(config.get_value("audio", "offset_ms", 0))

static func save_offset(value: int, device_key: String = "") -> void:
	var config := _config()
	if device_key.is_empty(): config.set_value("audio", "offset_ms", clampi(value, -300, 300))
	else: config.set_value("audio_device_offsets",device_key,clampi(value,-300,300))
	_save_config(config)


static func practice_avatar_id() -> StringName:
	var config := _config()
	var stored: Variant = config.get_value("appearance", "practice_avatar_id", HeritageAvatarCatalog.DEFAULT_AVATAR_ID)
	if not stored is String and not stored is StringName:
		return HeritageAvatarCatalog.DEFAULT_AVATAR_ID
	return HeritageAvatarCatalog.normalize(StringName(stored))


static func save_practice_avatar(avatar_id: StringName) -> bool:
	if not HeritageAvatarCatalog.is_known(avatar_id):
		return false
	var config := _config()
	config.set_value("appearance", "practice_avatar_id", String(avatar_id))
	return _save_config(config) == OK


static func visual_assistance_enabled() -> bool:
	var shared := _shared_settings()
	if shared != null: return shared.get_value("music_visual_assistance")
	var config := _config()
	return bool(config.get_value("display", "music_visual_assistance", true))


static func save_visual_assistance(enabled: bool) -> bool:
	var shared := _shared_settings()
	if shared != null:
		shared.set_value("music_visual_assistance", enabled)
		return true
	var config := _config()
	config.set_value("display", "music_visual_assistance", enabled)
	return _save_config(config) == OK


static func volume_percent() -> int:
	var shared := _shared_settings()
	if shared != null: return shared.get_value("minigame_volume")
	var config := _config()
	return clampi(int(config.get_value("audio", "volume_percent", 100)), 0, 100)


static func save_volume_percent(value: int) -> bool:
	var shared := _shared_settings()
	if shared != null:
		shared.set_value("minigame_volume", value)
		return true
	var config := _config()
	config.set_value("audio", "volume_percent", clampi(value, 0, 100))
	return _save_config(config) == OK


static func reduced_motion_enabled() -> bool:
	var shared := _shared_settings()
	if shared != null: return shared.get_value("reduce_motion")
	var config := _config()
	return bool(config.get_value("display", "reduce_motion", false))


static func input_bindings(profile: StringName) -> Dictionary:
	var config := _config()
	var value: Variant = config.get_value("input_bindings", String(profile), {})
	return value.duplicate(true) if value is Dictionary else {}


static func save_input_bindings(profile: StringName, bindings: Dictionary) -> bool:
	var config := _config()
	config.set_value("input_bindings", String(profile), bindings.duplicate(true))
	return _save_config(config) == OK


static func gamepad_glyph_style() -> String:
	var shared := _shared_settings()
	if shared != null: return shared.get_value("gamepad_glyph_style")
	var config := _config()
	var style := String(config.get_value("input", "gamepad_glyph_style", "position"))
	return style if style in ["position", "letters", "symbols"] else "position"


static func save_gamepad_glyph_style(style: String) -> bool:
	var shared := _shared_settings()
	if shared != null:
		shared.set_value("gamepad_glyph_style", style)
		return true
	if style not in ["position", "letters", "symbols"]: return false
	var config := _config()
	config.set_value("input", "gamepad_glyph_style", style)
	return _save_config(config) == OK


static func save_reduced_motion(enabled: bool) -> bool:
	var shared := _shared_settings()
	if shared != null:
		shared.set_value("reduce_motion", enabled)
		return true
	var config := _config()
	config.set_value("display", "reduce_motion", enabled)
	return _save_config(config) == OK


static func _save_config(config: ConfigFile) -> Error:
	config.set_value("format", "version", 2)
	var error := config.save(storage_path)
	if error != OK:
		push_warning("小游戏偏好保存失败：%s" % error_string(error))
	return error


static func _shared_settings() -> Node:
	# Isolated test stores retain their own settings and cannot touch player preferences.
	if storage_path != PATH: return null
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Settings") if tree != null else null
