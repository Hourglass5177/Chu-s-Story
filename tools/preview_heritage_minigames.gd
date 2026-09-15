extends SceneTree

## User-operated preview through the real main-menu gallery and practice Host.
## The existing debug shortcut reveals entries for this process only.
func _initialize() -> void:
	_open.call_deferred()

func _open() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	root.title = "楚物志 · 十五关效果试玩"
	var menu = load("res://main_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	for frame: int in 5: await process_frame
	if not menu.open_game_guide():
		push_error("小游戏预览未能打开指南。")
		return
	var guide = menu.get_game_guide()
	if not guide.is_developer_view_enabled():
		var reveal := InputEventKey.new()
		reveal.keycode = KEY_D
		reveal.ctrl_pressed = true
		reveal.shift_pressed = true
		reveal.pressed = true
		guide._input(reveal)
	guide.open_minigame_gallery()
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/user-minigame-preview.png")
	print("USER_MINIGAME_PREVIEW_READY: all 15 practice entries; process-only reveal")
