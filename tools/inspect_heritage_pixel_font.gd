extends SceneTree

## Isolated font inspection, with no character, gameplay, microphone or TV art.
## It deliberately keeps the real project's 2560x1600 canvas stretch.
const OUTPUT := "res://artifacts/pixel-font-v2"
var samples: Control
var measurements: Array[Dictionary] = []


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	_inspect.call_deferred()


func _inspect() -> void:
	for frame: int in 5: await process_frame
	root.mode = Window.MODE_WINDOWED
	root.content_scale_size = Vector2i(2560, 1600)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.title = "楚物志 · 纯文字字体检查"
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1600)]:
		root.size = dimensions
		for frame: int in 5: await process_frame
		samples = Control.new()
		root.add_child(samples)
		samples.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var paper := ColorRect.new()
		paper.color = HeritageTelevisionStyle.V2_CREAM
		samples.add_child(paper)
		paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for frame: int in 3: await process_frame
		var display_scale := (root.get_stretch_transform() * samples.get_global_transform_with_canvas()).get_scale().x
		var layout_scale := float(dimensions.x) / 1280.0
		var old_font := HeritageTelevisionStyle.pixel_font() as FontFile
		old_font.fixed_size = 0
		var native_font := HeritageTelevisionStyle.pixel_font() as FontFile
		var auxiliary := HeritageTelevisionStyle.pixel_font(true) as FontFile
		add_sample("旧方式：任意逻辑字号栅格化", old_font, 24.0 * layout_scale, Vector2(50, 60) * layout_scale, display_scale)
		add_sample("玩法教学  按住，追上金区  松开，让火候停下来", old_font, 24.0 * layout_scale, Vector2(50, 120) * layout_scale, display_scale)
		add_sample("新方式：保留原始十二像素字形", native_font, 24.0 * layout_scale, Vector2(50, 220) * layout_scale, display_scale)
		add_sample("玩法教学  按住，追上金区  松开，让火候停下来", native_font, 24.0 * layout_scale, Vector2(50, 280) * layout_scale, display_scale)
		add_sample("辅助文字：空格 添火  A 左行  D 右行  设置 返回", auxiliary, 20.0 * layout_scale, Vector2(50, 390) * layout_scale, display_scale)
		add_sample("已暂停  准备开始  本次练习结束", native_font, 36.0 * layout_scale, Vector2(50, 490) * layout_scale, display_scale)
		for frame: int in 5: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUTPUT + "/%d.png" % dimensions.x)
		measurements.append({"window": str(dimensions), "display_scale": display_scale, "native_font_cache_sizes": str(native_font.get_size_cache_list(0)), "old_font_cache_sizes": str(old_font.get_size_cache_list(0))})
		samples.free()
	var report := FileAccess.open(OUTPUT + "/font-rendering.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(measurements, "\t"))
	quit()


func add_sample(text: String, font: Font, physical_size: float, physical_position: Vector2, display_scale: float) -> void:
	var label := Label.new()
	label.text = text
	label.position = physical_position / display_scale
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", ceili(physical_size / display_scale))
	label.add_theme_constant_override("outline_size", 0)
	label.add_theme_color_override("font_color", HeritageTelevisionStyle.V2_INK)
	label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	samples.add_child(label)
