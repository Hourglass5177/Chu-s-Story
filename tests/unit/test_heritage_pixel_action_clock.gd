extends GutTest

func _canvas() -> HeritagePixelCanvas:
	var canvas := HeritagePixelCanvas.new()
	add_child_autofree(canvas)
	var appearance := HeritageAvatarAppearance.new()
	appearance.avatar_id = &"travel_blogger"
	appearance.sprite_frames = SpriteFrames.new()
	var frames := appearance.sprite_frames
	frames.add_animation(&"action")
	frames.set_animation_speed(&"action",10.0)
	frames.set_animation_loop(&"action",true)
	for duration: float in [1.0,2.0,1.0]: frames.add_frame(&"action",GradientTexture2D.new(),duration)
	frames.add_animation(&"release")
	frames.set_animation_speed(&"release",10.0)
	frames.set_animation_loop(&"release",false)
	for i: int in 2: frames.add_frame(&"release",GradientTexture2D.new())
	var art := HeritageTaskPresentation.new()
	art.version = 2
	art.avatar_appearances = {&"travel_blogger":appearance}
	canvas.artwork = art
	canvas.avatar_id = &"travel_blogger"
	return canvas

func test_action_entry_starts_at_first_frame_and_respects_authored_frame_duration() -> void:
	var canvas := _canvas()
	var frames := canvas.artwork.get_appearance(canvas.avatar_id).sprite_frames
	canvas.receive_visual_state({"action":&"action","animation_time":17.6})
	assert_eq(canvas.avatar_texture(&"action"),frames.get_frame_texture(&"action",0))
	canvas.receive_visual_state({"action":&"action","animation_time":17.72})
	assert_eq(canvas.avatar_texture(&"action"),frames.get_frame_texture(&"action",1))
	canvas.receive_visual_state({"action":&"action","animation_time":17.86})
	assert_eq(canvas.avatar_texture(&"action"),frames.get_frame_texture(&"action",1),"Double-duration middle frame is still active.")
	canvas.receive_visual_state({"action":&"action","animation_time":17.93})
	assert_eq(canvas.avatar_texture(&"action"),frames.get_frame_texture(&"action",2))
	canvas.receive_visual_state({"action":&"release","animation_time":18.08})
	assert_eq(canvas.avatar_texture(&"release"),frames.get_frame_texture(&"release",0),"New action ignores global-time frame position.")

func test_frozen_visual_clock_keeps_pose_and_nonloop_action_holds_final_frame() -> void:
	var canvas := _canvas()
	var frames := canvas.artwork.get_appearance(canvas.avatar_id).sprite_frames
	canvas.receive_visual_state({"action":&"release","animation_time":10.0})
	canvas.receive_visual_state({"action":&"release","animation_time":10.12})
	var frozen := canvas.avatar_texture(&"release")
	for i: int in 40:
		canvas.receive_visual_state({"action":&"release","animation_time":10.12})
	assert_almost_eq(canvas.local_action_time(),0.12,0.0001)
	assert_eq(canvas.avatar_texture(&"release"),frozen)
	for time: float in [10.3,10.5,10.7,10.9]:
		canvas.receive_visual_state({"action":&"release","animation_time":time})
	assert_eq(canvas.avatar_texture(&"release"),frames.get_frame_texture(&"release",1))
	canvas.receive_visual_state({"action":&"release","animation_time":0.0})
	assert_eq(canvas.avatar_texture(&"release"),frames.get_frame_texture(&"release",0),"A restarted challenge cannot keep the previous run's action time.")

func test_gameplay_pose_drives_motion_clock_when_generic_action_stays_ready() -> void:
	var canvas := _canvas()
	canvas.receive_visual_state({"action":&"ready","pose":&"action","animation_time":2.0})
	canvas.receive_visual_state({"action":&"ready","pose":&"action","animation_time":2.15})
	assert_almost_eq(canvas.local_action_time(),0.15,0.0001)
	canvas.receive_visual_state({"action":&"ready","pose":&"release","animation_time":2.2})
	assert_almost_eq(canvas.local_action_time(),0.0,0.0001)
