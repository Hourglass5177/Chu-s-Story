extends Node

## 开发期前端截图入口。只驱动公开前端接口，不参与发行版 UI 或玩法。

func _ready() -> void:
	var options := _parse_options(OS.get_cmdline_user_args())
	var width := maxi(int(options.get("width", "2560")), 640)
	var height := maxi(int(options.get("height", "1600")), 360)
	var screen_name := StringName(options.get("screen", "home"))
	var output_path := String(options.get("out", "artifacts/frontend/home.png"))
	var player_count := clampi(int(options.get("players", "0")), 0, SessionSetup.MAX_PLAYERS)
	get_window().size = Vector2i(width, height)

	var scene := load("res://main_menu.tscn") as PackedScene
	var menu := scene.instantiate() as MainMenu
	add_child(menu)
	await get_tree().process_frame
	if player_count > 0:
		_configure_capture_players(menu, player_count)
	menu.show_screen(screen_name, false)
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	else:
		await get_tree().process_frame
	var viewport_texture := get_viewport().get_texture()
	if viewport_texture == null:
		push_error("当前显示驱动不支持截图；请使用 Windows 显示驱动运行此工具。")
		get_tree().quit(2)
		return
	var image := viewport_texture.get_image()
	if image == null:
		push_error("当前显示驱动未返回可用图像。")
		get_tree().quit(2)
		return
	var absolute_output := output_path
	if not absolute_output.is_absolute_path():
		absolute_output = ProjectSettings.globalize_path("res://%s" % absolute_output)
	DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
	var error := image.save_png(absolute_output)
	if error != OK:
		push_error("前端截图保存失败：%s" % error_string(error))
		get_tree().quit(1)
		return
	print("FRONTEND_CAPTURE_OK ", screen_name, " ", image.get_size(), " -> ", absolute_output)
	get_tree().quit()


func _configure_capture_players(menu: MainMenu, player_count: int) -> void:
	if not menu.set_local_player_counts(player_count, 0):
		return
	var setup := menu.get("_draft") as SessionSetup
	var professions: Array = PlayerClass.PlayerCharacter.values()
	var regions: Array = MapSection.出生点坐标.keys()
	regions.sort()
	for index: int in mini(player_count, setup.players.size()):
		var player := setup.players[index]
		player.display_name = "玩家%d" % (index + 1)
		player.profession_type = int(professions[index])
		player.starting_region = int(regions[index])


func _parse_options(arguments: PackedStringArray) -> Dictionary[String, String]:
	var result: Dictionary[String, String] = {}
	for argument: String in arguments:
		if not argument.begins_with("--") or not argument.contains("="):
			continue
		var separator := argument.find("=")
		result[argument.substr(2, separator - 2)] = argument.substr(separator + 1)
	return result
