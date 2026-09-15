extends SceneTree

## Render actual independent Godot art scenes. Staged poses are not gameplay validation.
const TASKS := ["laohekou_si_xian", "tujia_saye_erhe", "jingzhou_hua_gu_xi", "han_ju", "ti_qin_xi", "gu_pen_ge"]
const AVATARS := ["travel", "life", "business", "food", "adventure", "magic"]
const POSES := ["ready", "prepare", "left_action", "right_action", "miss", "recover"]
var viewport: SubViewport
var records: Array[Dictionary] = []

func _initialize() -> void:
	root.size = Vector2i(1000, 600)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DirAccess.make_dir_recursive_absolute("res://artifacts/music-pixel-review")
	call_deferred("_run")

func _run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1000, 600)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(viewport)
	var preview := TextureRect.new()
	preview.texture = viewport.get_texture()
	preview.size = Vector2(1000, 600)
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(preview)
	for id: String in TASKS:
		var definition := load("res://InheritanceTasks/Definitions/%s.tres" % id) as HeritageTaskDefinition
		var art := definition.presentation
		assert(art != null and art.stage_scene != null, id)
		var stage := art.stage_scene.instantiate() as HeritagePixelCanvas
		stage.artwork = art
		stage.scale = Vector2.ONE
		viewport.add_child(stage)
		var sheet := Image.create(6000, 3600, false, Image.FORMAT_RGBA8)
		for row: int in 6:
			stage.avatar_id = StringName(AVATARS[row] + "_blogger")
			for column: int in 6:
				stage.receive_visual_state(_state(id, column))
				await process_frame
				await RenderingServer.frame_post_draw
				var frame := viewport.get_texture().get_image()
				frame.convert(Image.FORMAT_RGBA8)
				sheet.blit_rect(frame, Rect2i(0, 0, 1000, 600), Vector2i(column * 1000, row * 600))
				if row == 0:
					frame.save_png("res://artifacts/music-pixel-review/%s-%s.png" % [id, POSES[column]])
		var path := "res://artifacts/music-pixel-review/%s-six-avatars-six-poses.png" % id
		sheet.save_png(path)
		records.append({"task_id": id, "path": path, "rows": AVATARS, "columns": POSES})
		stage.queue_free()
		await process_frame
	var report := FileAccess.open("res://artifacts/music-pixel-review/report.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"method": "actual Godot pixel scene render, staged visual state", "normal_input_test": false, "captures": records}, "\t"))
	print("MUSIC_PIXEL_REVIEW_COMPLETE ", records.size(), " stages / 216 posed captures")
	quit()

func _state(id: String, column: int) -> Dictionary:
	var direction := 1 if column == 3 else -1
	var phase := "prepare" if column == 1 else ("action" if column in [2, 3] else ("miss" if column == 4 else ("recover" if column == 5 else "idle")))
	var state := {"animation_time": 1.0, "action_time": 0.1, "feedback_age": 0.35 if column >= 2 else 0.0, "cue": 0.78 if column == 1 else 0.0, "direction": direction, "player_direction": direction,
		"event_kind": "tap", "motion_phase": phase, "player_action": "ready", "visual_assistance": true, "active_hold": false,
		"feedback": "wrong_side" if column == 4 else "good", "release_cue": false, "lane": direction}
	match id:
		"laohekou_si_xian":
			state.player_action = "pluck"
			state.ensemble_turn = "player" if column in [1, 2, 3] else "partners"
		"tujia_saye_erhe": state.player_action = "step_left" if direction < 0 else "step_right"
		"jingzhou_hua_gu_xi":
			state.player_action = "voice_sustain"
			state.lead_singer_turn = column in [0, 4, 5]
			state.active_hold = column in [2, 3]
		"han_ju":
			state.actor_x = 0.7 if direction > 0 or column == 4 else 0.3
			state.actor_crossing = column == 1
			state.light_lane = direction
			state.light_on_actor = column != 4
		"ti_qin_xi":
			state.player_action = "bow_long_left" if direction < 0 else "bow_long_right"
			state.active_hold = column in [2, 3]
			state.hold_direction = direction
			state.hold_progress = 0.5
		"gu_pen_ge":
			state.teacher_frame = 2 if column == 1 else 0
			state.demonstrating = column == 1
	return state
