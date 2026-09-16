extends GutTest
const STORE := preload("res://UI/Settings/game_settings.gd")
var store: Node
var path: String
var legacy_path: String

func before_each() -> void:
	store = STORE.new()
	store.apply_runtime = false
	path = "user://test_settings_%d.cfg" % Time.get_ticks_usec()
	legacy_path = path + ".legacy"
	store.load_preferences(path, legacy_path)

func after_each() -> void:
	store.free()
	for file: String in [path, legacy_path]:
		if FileAccess.file_exists(file): DirAccess.remove_absolute(file)

func test_migration_keeps_legacy_progress_untouched() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "volume_percent", 35)
	config.set_value("display", "reduce_motion", true)
	config.set_value("input", "gamepad_glyph_style", "symbols")
	config.set_value("tutorial", "sugar", 6)
	config.save(legacy_path)
	var before := FileAccess.get_sha256(legacy_path)
	store.load_preferences(path, legacy_path)
	assert_eq(store.get_value("minigame_volume"), 35)
	assert_true(store.get_value("reduce_motion"))
	assert_eq(store.get_value("gamepad_glyph_style"), "symbols")
	store.set_value("master_volume", 70)
	assert_eq(store.flush(), OK)
	assert_eq(FileAccess.get_sha256(legacy_path), before)

func test_read_and_change_do_not_write_per_input() -> void:
	var reads: int = store.disk_reads
	for index in range(120):
		store.get_value("master_volume")
		store.set_value("master_volume", index % 100)
	assert_eq(store.disk_reads, reads)
	assert_eq(store.disk_writes, 0)
	store.flush()
	assert_eq(store.disk_writes, 1)
	store.flush()
	assert_eq(store.disk_writes, 1)

func test_reload_restores_preferences() -> void:
	store.set_value("sfx_volume", 45)
	store.set_value("fps_limit", 120)
	store.set_value("gamepad_glyph_style", "letters")
	store.flush()
	store.load_preferences(path, legacy_path)
	assert_eq(store.get_value("sfx_volume"), 45)
	assert_eq(store.get_value("fps_limit"), 120)
	assert_eq(store.get_value("gamepad_glyph_style"), "letters")

func test_reset_is_scoped_to_category() -> void:
	store.set_value("sfx_volume", 45)
	store.set_value("fps_limit", 120)
	store.set_value("reduce_motion", true)
	store.restore_page("audio")
	assert_eq(store.get_value("sfx_volume"), 100)
	assert_eq(store.get_value("fps_limit"), 120)
	assert_true(store.get_value("reduce_motion"))

func test_display_preview_never_saves_unconfirmed_mode() -> void:
	store.preview_display(1)
	assert_true(store.preview_active)
	assert_eq(store.get_value("display_mode"), 0)
	store.set_value("sfx_volume", 30)
	store.flush()
	var config := ConfigFile.new()
	config.load(path)
	assert_eq(config.get_value("settings", "display_mode"), 0)
	store.revert_display()
	assert_false(store.preview_active)
	assert_eq(store.get_value("display_mode"), 0)

func test_display_timeout_and_confirmation() -> void:
	store.preview_display(1)
	store._process(15.1)
	assert_false(store.preview_active)
	assert_eq(store.get_value("display_mode"), 0)
	store.preview_display(1)
	store.confirm_display()
	assert_false(store.preview_active)
	assert_eq(store.get_value("display_mode"), 1)
	store.load_preferences(path, legacy_path)
	assert_eq(store.get_value("display_mode"), 1)

func test_invalid_values_are_constrained() -> void:
	store.set_value("sfx_volume", -90)
	store.set_value("master_volume", 400)
	store.set_value("fps_limit", 17)
	store.set_value("gamepad_glyph_style", "wrong")
	assert_eq(store.get_value("sfx_volume"), 0)
	assert_eq(store.get_value("master_volume"), 100)
	assert_eq(store.get_value("fps_limit"), 60)
	assert_eq(store.get_value("gamepad_glyph_style"), "position")

func test_save_failure_retains_unsaved_state() -> void:
	store.storage_path = path + "/missing/settings.cfg"
	store.set_value("master_volume", 55)
	assert_ne(store.flush(), OK)
	assert_true(store.dirty)
	store.storage_path = path
	assert_eq(store.flush(), OK)
	assert_false(store.dirty)

func test_audio_gain_preserves_current_mix() -> void:
	var names := ["BoardMusic", "BoardSFX", "HeritageMinigames"]
	var created: Array[String] = []
	var backup := {}
	for bus: String in ["Master"] + names:
		var index := AudioServer.get_bus_index(bus)
		if index < 0:
			AudioServer.add_bus()
			index = AudioServer.bus_count - 1
			AudioServer.set_bus_name(index,bus)
			created.append(bus)
		backup[bus] = AudioServer.get_bus_volume_db(index)
	store.set_value("music_volume",50)
	store.apply_audio()
	assert_almost_eq(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index("BoardMusic")),db_to_linear(-10.0)*0.5,0.0001)
	assert_almost_eq(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index("BoardSFX")),db_to_linear(-5.0),0.0001)
	store.set_value("minigame_volume",0)
	store.apply_audio()
	assert_almost_eq(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index("HeritageMinigames")),0.0,0.0001)
	for bus: String in backup:
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(bus),backup[bus])
	for bus: String in created: AudioServer.remove_bus(AudioServer.get_bus_index(bus))
