class_name HeritagePixelStage
extends SubViewport

## Only art is rasterized here; task input, music and physics stay in logical units.
var artwork: HeritageTaskPresentation
var avatar_id: StringName
var visual_state: Dictionary = {}
var canvas: HeritagePixelCanvas


func configure(p_artwork: HeritageTaskPresentation, p_avatar_id: StringName) -> void:
	artwork = p_artwork
	avatar_id = p_avatar_id
	size = artwork.pixel_canvas_size
	disable_3d = true
	transparent_bg = false
	render_target_update_mode = SubViewport.UPDATE_ONCE
	canvas = artwork.stage_scene.instantiate() as HeritagePixelCanvas if artwork.stage_scene != null else HeritagePixelCanvas.new()
	canvas.artwork = artwork
	canvas.avatar_id = avatar_id
	canvas.size = Vector2(artwork.logical_stage_size)
	canvas.scale = Vector2(artwork.pixel_canvas_size) / Vector2(artwork.logical_stage_size)
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)


func update_state(state: Dictionary) -> void:
	visual_state = state
	canvas.receive_visual_state(state)
	# Render only when the owner advances the scene. Preparation, pause and
	# completed result portraits then keep their last texture without GPU work.
	render_target_update_mode = SubViewport.UPDATE_ONCE
