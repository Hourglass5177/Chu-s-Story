extends Node

## One in-memory preference owner; game progress remains in its existing stores.
signal changed(key: String, value: Variant)
signal save_finished(error: Error)
signal display_preview_changed(active: bool)

const PATH := "user://game_settings.cfg"
const DEFAULTS := {
	"master_volume": 100, "music_volume": 100, "sfx_volume": 100, "minigame_volume": 100,
	"display_mode": 0, "fps_limit": 60, "vsync": true,
	"reduce_motion": false, "music_visual_assistance": true, "gamepad_glyph_style": "position"
}
const PAGES := {
	"audio": ["master_volume", "music_volume", "sfx_volume", "minigame_volume"],
	"display": ["display_mode", "fps_limit", "vsync"],
	"accessibility": ["reduce_motion", "music_visual_assistance", "gamepad_glyph_style"]
}
var values: Dictionary = DEFAULTS.duplicate()
var storage_path := PATH
var disk_reads := 0
var disk_writes := 0
var dirty := false
var last_save_error: Error = OK
var preview_active := false
var preview_remaining := 0.0
var _preview_old := 0
var _preview_new := 0
var _window_size := Vector2i(1280, 720)
var _window_position := Vector2i(80, 80)
var _save_timer: Timer
var _panels: Array[WeakRef] = []
var _startup_mode := 0
var apply_runtime := true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	apply_runtime = DisplayServer.get_name() != "headless"
	if apply_runtime:
		_startup_mode = 0 if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED else 1
		_window_size = DisplayServer.window_get_size()
		_window_position = DisplayServer.window_get_position()
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.5
	_save_timer.timeout.connect(flush)
	add_child(_save_timer)
	load_preferences(PATH, HeritageMinigamePreferences.PATH)
	if apply_runtime:
		apply_audio()
		_apply_frame_options()
		if FileAccess.file_exists(PATH): _apply_mode(int(get_value("display_mode")))
	set_process(false)

func load_preferences(path: String, legacy_path: String) -> void:
	storage_path = path
	values = DEFAULTS.duplicate()
	values.display_mode = _startup_mode
	var config := ConfigFile.new()
	disk_reads += 1
	var status := config.load(path)
	if status == OK:
		for key: String in DEFAULTS:
			values[key] = _sanitize(key, config.get_value("settings", key, values[key]))
		var size_value: Variant = config.get_value("window", "size", _window_size)
		var pos_value: Variant = config.get_value("window", "position", _window_position)
		if size_value is Vector2i: _window_size = size_value
		if pos_value is Vector2i: _window_position = pos_value
	else:
		var legacy := ConfigFile.new()
		disk_reads += 1
		if legacy.load(legacy_path) == OK:
			values.minigame_volume = _sanitize("minigame_volume", legacy.get_value("audio", "volume_percent", 100))
			values.reduce_motion = _sanitize("reduce_motion", legacy.get_value("display", "reduce_motion", false))
			values.music_visual_assistance = _sanitize("music_visual_assistance", legacy.get_value("display", "music_visual_assistance", true))
			values.gamepad_glyph_style = _sanitize("gamepad_glyph_style", legacy.get_value("input", "gamepad_glyph_style", "position"))
		# Do not overwrite unreadable files until the player explicitly changes a setting.
	dirty = false
	last_save_error = OK

func _sanitize(key: String, value: Variant) -> Variant:
	if key.ends_with("_volume"):
		return clampi(int(value), 0, 100) if value is int or value is float else DEFAULTS[key]
	if key == "fps_limit": return int(value) if value in [0, 30, 60, 120] else 60
	if key == "display_mode": return int(value) if value in [0, 1] else _startup_mode
	if key == "gamepad_glyph_style": return value if value in ["position", "letters", "symbols"] else "position"
	return value if value is bool else DEFAULTS[key]

func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))

func set_value(key: String, value: Variant) -> void:
	if not DEFAULTS.has(key): return
	var next: Variant = _sanitize(key, value)
	if values[key] == next: return
	if key == "display_mode":
		preview_display(int(next))
		return
	values[key] = next
	_mark_dirty()
	if apply_runtime:
		if key.ends_with("_volume"): apply_audio()
		elif key in ["fps_limit", "vsync"]: _apply_frame_options()
	changed.emit(key, next)

func _mark_dirty() -> void:
	dirty = true
	if is_instance_valid(_save_timer): _save_timer.start()

func flush() -> Error:
	if not dirty: return last_save_error
	var config := ConfigFile.new()
	for key: String in DEFAULTS: config.set_value("settings", key, values[key])
	config.set_value("format", "version", 1)
	config.set_value("window", "size", _window_size)
	config.set_value("window", "position", _window_position)
	disk_writes += 1
	last_save_error = config.save(storage_path)
	if last_save_error == OK: dirty = false
	save_finished.emit(last_save_error)
	return last_save_error

func restore_page(page: String) -> void:
	for key: String in PAGES.get(page, []):
		set_value(key, _startup_mode if key == "display_mode" else DEFAULTS[key])

func apply_audio() -> void:
	for bus: String in ["Master", "BoardMusic", "BoardSFX", "HeritageMinigames"]:
		var index := AudioServer.get_bus_index(bus)
		if index < 0: continue
		var key := {"Master":"master_volume", "BoardMusic":"music_volume", "BoardSFX":"sfx_volume", "HeritageMinigames":"minigame_volume"}[bus] as String
		var base_db := -10.0 if bus == "BoardMusic" else -5.0 if bus == "BoardSFX" else 0.0
		AudioServer.set_bus_volume_linear(index, db_to_linear(base_db) * float(values[key]) / 100.0)

func _apply_frame_options() -> void:
	Engine.max_fps = int(values.fps_limit)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(values.vsync) else DisplayServer.VSYNC_DISABLED)

func preview_display(mode: int) -> void:
	if preview_active: revert_display()
	if mode == int(values.display_mode): return
	_preview_old = int(values.display_mode)
	_preview_new = mode
	preview_active = true
	preview_remaining = 15.0
	if apply_runtime: _apply_mode(mode)
	set_process(true)
	display_preview_changed.emit(true)

func confirm_display() -> void:
	if not preview_active: return
	values.display_mode = _preview_new
	preview_active = false
	set_process(false)
	_mark_dirty()
	changed.emit("display_mode", values.display_mode)
	display_preview_changed.emit(false)
	flush()

func revert_display() -> void:
	if not preview_active: return
	if apply_runtime: _apply_mode(_preview_old)
	preview_active = false
	set_process(false)
	display_preview_changed.emit(false)

func _process(delta: float) -> void:
	preview_remaining -= delta
	if preview_remaining <= 0.0: revert_display()

func _apply_mode(mode: int) -> void:
	if mode == 1:
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
			_window_size = DisplayServer.window_get_size()
			_window_position = DisplayServer.window_get_position()
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var area := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
		_window_size = _window_size.clamp(Vector2i(640, 480).min(area.size), area.size)
		_window_position = _window_position.clamp(area.position, area.end - _window_size)
		DisplayServer.window_set_size(_window_size)
		DisplayServer.window_set_position(_window_position)

func is_panel_open() -> bool:
	for ref: WeakRef in _panels:
		var panel: Variant = ref.get_ref()
		if is_instance_valid(panel) and panel.visible: return true
	return false

func register_panel(panel: Control) -> void:
	_panels = _panels.filter(func(ref: WeakRef) -> bool: return is_instance_valid(ref.get_ref()))
	_panels.append(weakref(panel))

func _exit_tree() -> void:
	revert_display()
	flush()
