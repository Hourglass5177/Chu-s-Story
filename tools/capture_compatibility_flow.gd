extends "res://tools/frontend_session_e2e_runner.gd"

## Native rendering of the existing real-pointer, two-session regression.
## Capture outside performance intervals; no skipped launch or map injection.
var _capture_index := 0

func _start_session(profession_position: int, region_position: int, display_name: String, exercise_interaction_chain: bool) -> int:
	var result := await super._start_session(profession_position,region_position,display_name,exercise_interaction_chain)
	if result>0:
		_capture_index+=1
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://artifacts/performance-gallery")
		get_viewport().get_texture().get_image().save_png("res://artifacts/performance-gallery/map-%d.png"%_capture_index)
	return result
