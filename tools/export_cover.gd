extends Node

func _ready() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var background := TextureRect.new()
	background.texture = MainUI.texture("home")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.size = Vector2(1920, 1080)
	viewport.add_child(background)
	var logo := TextureRect.new()
	logo.texture = MainUI.texture("logo")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.position = Vector2(802, 28)
	logo.size = Vector2(316, 316)
	viewport.add_child(logo)
	var caption := Label.new()
	caption.text = "湖北非遗主题 · 探索策略桌游"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.position = Vector2(0, 1008)
	caption.size = Vector2(1920, 48)
	MainUI.label(caption, 34, true)
	caption.add_theme_color_override("font_shadow_color", Color("fff4dc"))
	caption.add_theme_constant_override("shadow_offset_x", 1)
	caption.add_theme_constant_override("shadow_offset_y", 1)
	viewport.add_child(caption)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts/cover")
	var output := "res://artifacts/cover/楚物志封面-1920x1080.png"
	var picture := viewport.get_texture().get_image()
	assert(picture.get_size() == Vector2i(1920, 1080))
	var result := picture.save_png(output)
	print("COVER_EXPORT ", result, " ", output)
	get_tree().quit(result)
