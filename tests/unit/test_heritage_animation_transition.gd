extends GutTest

func test_selected_animation_owns_its_start_clock_and_freezes_between_updates() -> void:
	var canvas := autofree(HeritagePixelCanvas.new()) as HeritagePixelCanvas
	var appearance := HeritageAvatarAppearance.new()
	appearance.avatar_id = &"travel_blogger"
	appearance.sprite_frames = SpriteFrames.new()
	var first := GradientTexture1D.new()
	var second := GradientTexture1D.new()
	for name: StringName in [&"ready", &"prepare", &"release"]:
		appearance.sprite_frames.add_animation(name)
		appearance.sprite_frames.set_animation_speed(name, 10)
		appearance.sprite_frames.set_animation_loop(name, false)
		appearance.sprite_frames.add_frame(name, first)
		appearance.sprite_frames.add_frame(name, second)
	canvas.artwork = HeritageTaskPresentation.new()
	canvas.artwork.avatar_appearances[appearance.avatar_id] = appearance
	canvas.avatar_id = appearance.avatar_id
	canvas.receive_visual_state({"song_time_ms":7511, "action_serial":1})
	assert_same(canvas.avatar_texture(&"ready"), first)
	canvas.receive_visual_state({"song_time_ms":7711, "action_serial":1})
	assert_same(canvas.avatar_texture(&"ready"), second)
	assert_same(canvas.avatar_texture(&"prepare"), first, "No input is required to restart the preparation clip")
	assert_same(canvas.avatar_texture(&"prepare"), first, "Redraws while paused do not advance time")
	canvas.receive_visual_state({"song_time_ms":7911, "action_serial":1})
	assert_same(canvas.avatar_texture(&"prepare"), second)
	canvas.receive_visual_state({"song_time_ms":8011, "action_serial":2})
	assert_same(canvas.avatar_texture(&"prepare"), first, "A new stroke restarts even the same animation")
	canvas.receive_visual_state({"song_time_ms":0, "action_serial":2})
	assert_same(canvas.avatar_texture(&"prepare"), first, "A new teaching excerpt cannot inherit the previous clock")
