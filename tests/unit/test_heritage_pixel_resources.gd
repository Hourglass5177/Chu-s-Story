extends GutTest

## Asset-contract checks only, not a claim that the generated art is good.
func test_all_fifteen_presentations_have_six_complete_bounded_appearances() -> void:
	var count := 0
	for filename: String in DirAccess.get_files_at("res://InheritanceTasks/Definitions"):
		if not filename.ends_with(".tres"): continue
		var definition := load("res://InheritanceTasks/Definitions/" + filename) as HeritageTaskDefinition
		var art := definition.presentation
		assert_not_null(art, filename)
		if art == null: continue
		count += 1
		# Presentation resolution may preserve a generated master's detail. It
		# must retain the logical aspect ratio and never change gameplay scale.
		assert_true(art.pixel_canvas_size in [Vector2i(500,300),Vector2i(1000,600)], filename)
		assert_eq(art.pixel_canvas_size.x * 3, art.pixel_canvas_size.y * 5)
		if definition.task_id != &"xiabaoping_minjian_gushi":
			assert_eq(art.pixel_canvas_size,Vector2i(1000,600),filename+": Keep the approved source detail through the art viewport")
		assert_eq(art.logical_stage_size, Vector2i(1000, 600))
		assert_not_null(art.background)
		assert_not_null(art.cover)
		assert_eq(art.avatar_appearances.size(), 6)
		for avatar: StringName in art.avatar_appearances:
			var appearance := art.get_appearance(avatar)
			assert_not_null(appearance)
			assert_eq(appearance.avatar_id, avatar)
			assert_eq(appearance.costume_id, definition.task_id)
			assert_not_null(appearance.portrait)
			assert_not_null(appearance.sprite_frames)
			assert_false(appearance.sprite_frames.get_animation_names().is_empty())
			for animation: StringName in appearance.sprite_frames.get_animation_names():
				assert_gt(appearance.sprite_frames.get_frame_count(animation), 0)
				for index: int in appearance.sprite_frames.get_frame_count(animation):
					var frame := appearance.sprite_frames.get_frame_texture(animation, index) as AtlasTexture
					assert_not_null(frame)
					if frame != null:
						assert_true(Rect2(Vector2.ZERO, frame.atlas.get_size()).encloses(frame.region), "%s %s %s" % [filename, avatar, animation])
		if definition.task_id == &"xiabaoping_minjian_gushi":
			var catalog := preload("res://InheritanceTasks/Data/story_puzzle_catalog.gd")
			for story: int in 3:
				for scene: int in 3:
					var path := catalog.image_path(story,scene)
					assert_true(ResourceLoader.exists(path),path)
					var panel := load(path) as Texture2D
					assert_not_null(panel, path)
					if panel != null:
						assert_eq(panel.get_size(),Vector2(724,724),"Keep each of the nine source panels at native resolution")
					# The controller shares this texture with the reference preview;
					# test_xiabaoping_story checks identity instead of a low-res copy.
		else: assert_not_null(art.stage_scene)
	assert_eq(count, 15)
