extends SceneTree

## External script for the exported Release executable. Only built-in types are
## named here; game scripts/resources are loaded from the executable's PCK.
## No WindowsVocalCapture instance or microphone stream is ever constructed.
const MODEL := "res://InheritanceTasks/AudioNative/models/crepe_tiny.onnx"
const RUNTIME_ART := "res://InheritanceTasks/Art/Pixel/v1/runtime"
const AVATARS: Array[StringName] = [&"travel_blogger", &"life_blogger", &"business_blogger", &"food_blogger", &"adventure_blogger", &"magic_blogger"]
var failures: Array[String] = []
var report: Dictionary = {"microphone_opened":false, "tasks":[], "media":[], "runtime_textures":0, "avatar_sets":0}
var report_path: String
var capture_path: String
var stages: Array[Node] = []
var media_paths: Dictionary = {}

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="): report_path = argument.trim_prefix("--report=")
		elif argument.begins_with("--capture="): capture_path = argument.trim_prefix("--capture=")
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	if not ok:
		failures.append(description)
		push_error("RELEASE_PIXEL_CHECK: " + description)

func _run() -> void:
	await process_frame
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(1280,720)
	report.engine = Engine.get_version_info()
	report.executable = OS.get_executable_path()
	report.version = ProjectSettings.get_setting("application/config/version", "")
	report.debug_build = OS.is_debug_build()
	report.renderer = RenderingServer.get_current_rendering_driver_name()
	check(not OS.has_feature("editor") and not OS.is_debug_build(), "must run the actual Release executable")
	check(str(report.renderer).to_lower() == "d3d12", "actual D3D12 renderer")
	check(not ResourceLoader.exists("res://InheritanceTasks/Art/Pixel/v1/source/tv.png"), "source artwork excluded from package")
	check(not ResourceLoader.exists("res://tools/verify_release_pixel.gd"), "verification tools excluded from package")
	var manager = root.get_node_or_null("HeritageTaskManager")
	check(manager != null, "heritage manager autoload")
	var definitions: Dictionary = manager.get("_definitions") if manager != null else {}
	check(definitions.size() == 15, "15 task definitions")
	var index := 0
	for definition: Resource in definitions.values():
		await _check_task(definition, index)
		index += 1
	_load_runtime_textures(RUNTIME_ART)
	check(int(report.runtime_textures) > 40, "packed runtime art catalog")
	check(int(report.avatar_sets) == 90, "all 15 by 6 avatar action sets")
	media_paths["res://arts/非遗媒体资源/数字版/2026-09-09/xingshan-xiatianhaozi-v1.ogg"] = "audio"
	media_paths["res://InheritanceTasks/Audio/action-feedback.wav"] = "audio"
	for path: String in media_paths:
		await _check_media(path)
	check(ResourceLoader.load("res://main_menu.tscn") is PackedScene, "main menu scene")
	check(ResourceLoader.load("res://main_map.tscn") is PackedScene, "main map scene")
	check(ResourceLoader.load("res://InheritanceTasks/UI/heritage_task_host.tscn") is PackedScene, "television Host scene")
	var catalog = load("res://UI/GameGuide/manual_catalog.gd").load_generated()
	check(catalog.load_error.is_empty(), "packed game guide JSON")
	report.guide_loaded = catalog.load_error.is_empty()
	await _check_model()
	if not capture_path.is_empty():
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(capture_path) == OK, "Release visual contact sheet")
	for stage: Node in stages: stage.queue_free()
	stages.clear()
	for frame: int in 3: await process_frame
	report.failures = failures
	report.status = "PASS" if failures.is_empty() else "FAIL"
	if not report_path.is_empty():
		var file := FileAccess.open(report_path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report, "\t"))
			file.close()
		else: check(false, "write validation report")
	print("RELEASE_PIXEL_CHECK ", report.status, " tasks=", report.tasks.size(), " avatars=", report.avatar_sets, " textures=", report.runtime_textures, " media=", report.media.size(), " microphone=false")
	quit(0 if failures.is_empty() else 1)

func _check_task(definition: Resource, index: int) -> void:
	var id := str(definition.get("task_id"))
	print("RELEASE_PIXEL_TASK ", id)
	check(bool(definition.call("is_valid_definition")), id + " definition")
	var instance = definition.call("instantiate_task")
	check(instance != null, id + " task scene")
	if instance != null: instance.free()
	var artwork: Resource = definition.get("presentation")
	check(artwork != null, id + " presentation")
	if artwork == null: return
	check(artwork.get("background") is Texture2D and artwork.get("cover") is Texture2D, id + " background and cover")
	var stage = load("res://InheritanceTasks/Presentation/heritage_pixel_stage.gd").new()
	stage.call("configure", artwork, AVATARS[0])
	root.add_child(stage)
	stages.append(stage)
	for avatar: StringName in AVATARS:
		var appearance: Resource = artwork.call("get_appearance", avatar)
		check(appearance != null, id + " " + str(avatar))
		if appearance == null: continue
		check(appearance.get("portrait") is Texture2D, id + " avatar portrait")
		var frames: SpriteFrames = appearance.get("sprite_frames")
		check(frames != null and not frames.get_animation_names().is_empty(), id + " avatar animations")
		if frames != null:
			for action: StringName in frames.get_animation_names():
				check(frames.get_frame_count(action) > 0, id + " " + str(action) + " frames")
				for frame: int in frames.get_frame_count(action):
					var texture := frames.get_frame_texture(action, frame)
					check(texture != null and texture.get_width() > 0, id + " valid animation texture")
		stage.set("avatar_id", avatar)
		stage.get("canvas").set("avatar_id", avatar)
		stage.call("update_state", {"action":&"ready", "animation_time":0.0, "listening":false})
		await RenderingServer.frame_post_draw
		var image: Image = stage.get_texture().get_image()
		check(not image.is_empty() and image.get_size() == Vector2i(500,300), id + " render " + str(avatar))
		report.avatar_sets += 1
	stage.set("avatar_id", AVATARS[0])
	stage.get("canvas").set("avatar_id", AVATARS[0])
	stage.call("update_state", {"action":&"ready", "animation_time":0.0, "listening":false})
	var tile := TextureRect.new()
	tile.texture = stage.get_texture()
	tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tile.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tile.position = Vector2(12+(index%5)*253, 32+(index/5)*225)
	tile.size = Vector2(241,145)
	root.add_child(tile)
	stages.append(tile)
	var title := Label.new()
	title.position = tile.position+Vector2(0,150)
	title.size = Vector2(241,60)
	title.text = str(definition.get("heritage_name"))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size",18)
	root.add_child(title)
	stages.append(title)
	var panels: Array = artwork.get("story_panels")
	var thumbnails: Array = artwork.get("story_thumbnails")
	var poses: Array = artwork.get("story_animation")
	if id == "xiabaoping_minjian_gushi":
		check(panels.size() == 4 and thumbnails.size() == 4 and poses.size() == 12, "story panels, cards, poses")
		if not panels.is_empty(): tile.texture = panels[0]
	var chart: Resource = definition.get("music_chart")
	if chart != null:
		check(str(chart.call("validate")).is_empty(), id + " music chart")
		var path: String = chart.get("audio_path")
		# Imported Ogg streams may replace the source container in a PCK. Validate
		# its recorded identity and the actual decoder; hash raw bytes when retained.
		if FileAccess.file_exists(path):
			check(FileAccess.get_sha256(path) == str(chart.get("audio_sha256")), id + " unchanged source audio hash")
		media_paths[path] = "audio"
	for field: String in ["reference_video_path", "reference_audio_path", "reference_analysis_path"]:
		var path: String = definition.get(field)
		if not path.is_empty(): media_paths[path] = "reference"
	report.tasks.append({"id":id, "presentation_version":artwork.get("version"), "avatars":6, "story_poses":poses.size()})

func _load_runtime_textures(directory: String) -> void:
	for file_name: String in DirAccess.get_files_at(directory):
		var name := file_name.trim_suffix(".remap")
		if not name.ends_with(".png"): continue
		var path := directory.path_join(name)
		var texture := ResourceLoader.load(path) as Texture2D
		check(texture != null and texture.get_width() > 0, "runtime texture " + path)
		report.runtime_textures += 1
	for child: String in DirAccess.get_directories_at(directory):
		_load_runtime_textures(directory.path_join(child))

func _check_media(path: String) -> void:
	if path.ends_with(".json"):
		var content = JSON.parse_string(FileAccess.get_file_as_string(path))
		check(content != null, "reference analysis " + path)
		report.media.append({"path":path, "json_loaded":content != null})
		return
	var media := ResourceLoader.load(path)
	check(media != null, "packed media " + path)
	if media is AudioStream:
		var audio := AudioStreamPlayer.new()
		audio.stream = media
		audio.volume_db = -80
		root.add_child(audio)
		audio.play()
		var started := audio.playing
		await create_timer(.04).timeout
		var position := audio.get_playback_position()
		check(started and (position > 0 or media.get_length() <= .05), "decoded audio playback " + path)
		report.media.append({"path":path, "length":media.get_length(), "playback_position":position})
		audio.stop()
		audio.stream = null
		audio.queue_free()
	elif media is VideoStream:
		var video := VideoStreamPlayer.new()
		video.stream = media
		video.volume_db = -80
		root.add_child(video)
		video.play()
		await create_timer(.25).timeout
		var texture := video.get_video_texture()
		var decoded := texture != null and texture.get_width() > 0 and video.stream_position > 0
		check(decoded, "decoded video frame " + path)
		report.media.append({"path":path, "decoded":decoded, "playback_position":video.stream_position})
		video.stop()
		video.stream = null
		video.queue_free()
	else: check(false, "supported media format " + path)

func _check_model() -> void:
	check(ClassDB.class_exists(&"CrepePitchExtractor"), "native Release ONNX adapter")
	check(ClassDB.class_exists(&"WindowsVocalCapture"), "native capture class registration only")
	var model_bytes := FileAccess.get_file_as_bytes(MODEL)
	check(not model_bytes.is_empty(), "model bytes contained in PCK")
	if model_bytes.is_empty() or not ClassDB.class_exists(&"CrepePitchExtractor"): return
	var extractor = ClassDB.instantiate(&"CrepePitchExtractor")
	var initialized: bool = extractor.call(&"initialize_model", model_bytes)
	check(initialized and bool(extractor.call(&"is_ready")), "initialize_model(bytes): " + str(extractor.call(&"get_last_error")))
	report.model_initialized = initialized
	report.model_bytes = model_bytes.size()
	report.model_sha256 = FileAccess.get_sha256(MODEL)
	var lifetime: WeakRef = weakref(extractor)
	extractor = null
	model_bytes.clear()
	await process_frame
	report.model_released = lifetime.get_ref() == null
	check(bool(report.model_released), "native model destructor completed before process exit")
