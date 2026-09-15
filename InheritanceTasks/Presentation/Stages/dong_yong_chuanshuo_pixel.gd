extends HeritagePixelCanvas
const ART := "res://InheritanceTasks/Art/Pixel/v3/runtime/dong/"
var _pose_anchors: Dictionary = {}
var _body_lean := 0.0
var _bridge_anchors: Dictionary = {}
const VIEW_ZOOM := 1.2
const VIEW_FOCUS := Vector2(300,380)

func _ready() -> void:
	# These are original-resolution crops, not 1:1 low-resolution sprites.
	# Sampling a moving, rotated wheel with nearest loses thin rim segments.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED

func _view_transform(origin: Vector2, angle: float = 0.0) -> void:
	# One camera transform covers the cart, both feet and every road sample.
	# Only display changes; contacts, travel and braking stay in world units.
	draw_set_transform(VIEW_FOCUS+(origin-VIEW_FOCUS)*VIEW_ZOOM,angle,Vector2.ONE*VIEW_ZOOM)

func _display_size(texture: Texture2D, height: float) -> Vector2:
	return texture.get_size()*(height/texture.get_height())

func paint() -> void:
	paint_asset(ART+"background.png",Rect2(0,0,1000,600))
	_view_transform(Vector2.ZERO)
	var distance := float(visual_state.get("distance",20.0))
	var camera := distance-370.0
	var samples: PackedVector2Array = visual_state.get("road_samples",PackedVector2Array())
	var ground := asset(ART+"ground.png")
	var bridge_start := float(visual_state.get("bridge_start",1660.0))
	var bridge_end := float(visual_state.get("bridge_end",2040.0))
	for i: int in range(1,samples.size()):
		var a := samples[i-1]-Vector2(camera,0)
		var b := samples[i]-Vector2(camera,0)
		if b.x < 0 or a.x > 1000 or (samples[i-1].x>=bridge_start and samples[i].x<=bridge_end): continue
		draw_colored_polygon(PackedVector2Array([a,b,Vector2(b.x,600),Vector2(a.x,600)]),Color("77543a"))
		if ground != null:
			var u0 := samples[i-1].x/512.0
			var u1 := samples[i].x/512.0
			# Continuous UVs follow both slope vertices. Region-clipped vertical
			# strips introduced a dark seam every ten units with linear sampling.
			draw_polygon(PackedVector2Array([a,b,b+Vector2(0,64),a+Vector2(0,64)]),
				PackedColorArray([Color.WHITE,Color.WHITE,Color.WHITE,Color.WHITE]),
				PackedVector2Array([Vector2(u0,0),Vector2(u1,0),Vector2(u1,1),Vector2(u0,1)]),ground)
	var start := bridge_start-camera
	var finish := bridge_end-camera
	var bridge := asset(ART+"bridge.png")
	var rail := asset(ART+"rail.png")
	if rail!=null:
		for x: int in range(int(start),int(finish),128):
			draw_texture_rect(rail,Rect2(x,405,128,48),false)
	if bridge!=null:
		if _bridge_anchors.is_empty():
			_bridge_anchors = JSON.parse_string(FileAccess.get_file_as_string(ART+"bridge-anchors.json"))
		# The generated board is oblique: its upper walking face ends at source
		# row 68, before the dark vertical front face begins at row 70. Align
		# that contact edge, not the texture's top border, with world y=450.
		var deck_height := float(_bridge_anchors.logical_height)
		var surface_offset := float(_bridge_anchors.surface_y_px)/bridge.get_height()*deck_height
		draw_texture_rect(bridge,Rect2(start,450-surface_offset,finish-start,deck_height),false)
	var offset := Vector2(camera,0)
	var axle: Vector2 = visual_state.get("axle",Vector2(distance,416))-offset
	var contacts := contact_pose()
	var angle := float(contacts.cart_angle)
	var handle: Vector2 = contacts.handle-offset
	# Preserve the intact generated shoulders, bent elbows and wrists. The cart
	# handles follow the fists; anatomy is never stretched to bridge a gap.
	var body: Dictionary = contacts.body.duplicate()
	for point: String in ["origin","near_grip","far_grip","hip"]: body[point] -= offset
	var far_handle: Vector2 = body.far_grip
	_segment(ART+"shaft.png",far_handle,axle+Vector2(40,-48).rotated(angle),5.0,0.0)
	_segment(ART+"shaft.png",handle,axle+Vector2(45,-31).rotated(angle),6.0,0.0)
	_view_transform(axle.round(),angle)
	paint_asset(ART+"father-chibi-v8.png",Rect2(Vector2(-4,-142),_display_size(asset(ART+"father-chibi-v8.png"),120)))
	var cart := asset(ART+"cart.png")
	# The original cart includes two long shafts. Draw only its load bed here;
	# drawing those shafts as well would duplicate the two contact-driven ones.
	var bed_start := 385.0
	var bed_width := cart.get_width()-bed_start
	draw_texture_rect_region(cart,Rect2(-179+244*bed_start/cart.get_width(),-87,244*bed_width/cart.get_width(),76),Rect2(bed_start,0,bed_width,cart.get_height()))
	paint_asset(ART+"bundle.png",Rect2(22,-54,32,30))
	_view_transform(Vector2.ZERO)
	_segment(ART+"shaft.png",axle,axle+Vector2(0,-45).rotated(angle),8.0,0.0)
	_view_transform(axle.round(),float(visual_state.get("wheel_angle",0.0)))
	paint_asset(ART+"wheel.png",Rect2(-24,-24,48,48))
	_view_transform(Vector2.ZERO)
	_pusher(offset,body,contacts.feet)
	draw_set_transform(Vector2.ZERO)

func _segment(path: String, from: Vector2, to: Vector2, width: float, source_rotation: float = PI*.5) -> void:
	var texture := asset(path)
	if texture==null:return
	var v := to-from
	# Limb sources point down. The generated shaft source points right.
	_view_transform(from.round(),v.angle()-source_rotation)
	if is_zero_approx(source_rotation): draw_texture_rect(texture,Rect2(0,-width*.5,v.length()+2,width),false)
	else: draw_texture_rect(texture,Rect2(-width*.5,-2,width,v.length()+4),false)
	_view_transform(Vector2.ZERO)

func _part(name: String) -> String:
	return ART+str(avatar_id)+"/"+name+".png"

func receive_visual_state(state: Dictionary) -> void:
	var previous_time := float(visual_state.get("animation_time",0.0))
	var elapsed := clampf(float(state.get("animation_time",0.0))-previous_time,0.0,.25)
	var next_pose := StringName(state.get("pose",&"idle"))
	var target := .075 if next_pose in [&"push",&"push_uphill"] else (-.07 if next_pose==&"brake" else 0.0)
	_body_lean = move_toward(_body_lean,target,elapsed*.65)
	super.receive_visual_state(state)

func _point(value: Array) -> Vector2:
	return Vector2(float(value[0]),float(value[1]))

func pusher_pose(grip: Vector2) -> Dictionary:
	if _pose_anchors.is_empty():
		_pose_anchors = JSON.parse_string(FileAccess.get_file_as_string(ART+"intact-pose-anchors-v8.json"))
	var points: Dictionary = _pose_anchors.avatars[str(avatar_id)]
	var reference := asset(_part("reference"))
	var scale_factor := float(_pose_anchors.display_height)/reference.get_height()
	var near := _point(points.near_grip)
	var origin := grip-(near*scale_factor).rotated(_body_lean)
	return {"origin":origin,"angle":_body_lean,"scale":scale_factor,"texture":reference,
		"cut_y":float(points.cut_y),"near_grip":grip,
		"far_grip":origin+(_point(points.far_grip)*scale_factor).rotated(_body_lean),
		"hip":origin+(_point(points.hip)*scale_factor).rotated(_body_lean)}

func _ground_at(x: float) -> float:
	var road: Array = visual_state.get("road",[])
	for i: int in range(1,road.size()):
		if x <= road[i].x:
			var t := clampf(inverse_lerp(road[i-1].x,road[i].x,x),0.0,1.0)
			return lerpf(road[i-1].y,road[i].y,t*t*(3.0-2.0*t))
	return float(road[-1].y) if not road.is_empty() else 440.0

func contact_pose() -> Dictionary:
	var axle: Vector2 = visual_state.get("axle",Vector2(20,416))
	var template := pusher_pose(Vector2.ZERO)
	var grip_from_hip: Vector2 = -template.hip
	var reference: Texture2D = template.texture
	var points: Dictionary = _pose_anchors.avatars[str(avatar_id)]
	var leg_height := (reference.get_height()-float(points.hip[1]))*float(template.scale)
	var angle := float(visual_state.get("cart_angle",0.0))
	# Solve the cart tilt and the actor's position together. The actor keeps
	# its original height and anatomy, including when straddling a slope break.
	for i: int in 8:
		var local := Vector2(-153,-31).rotated(angle)
		var hip_x := axle.x+local.x-grip_from_hip.x
		var target_y := _ground_at(hip_x)-leg_height+grip_from_hip.y
		var slope := (_ground_at(hip_x+1)-_ground_at(hip_x-1))*.5
		var derivative := minf(-40,local.x+slope*local.y)
		angle = clampf(angle-(axle.y+local.y-target_y)/derivative,-.65,.65)
	var handle := axle+Vector2(-153,-31).rotated(angle)
	var body := pusher_pose(handle)
	var old_hip: Vector2 = visual_state.get("hip",Vector2.ZERO)
	var feet: Array[Vector2] = []
	for old_foot: Vector2 in visual_state.get("feet",[]):
		var lift := clampf(_ground_at(old_foot.x)-old_foot.y,0,10)
		var x := old_foot.x+float(body.hip.x)-old_hip.x
		feet.append(Vector2(x,_ground_at(x)-lift))
	return {"cart_angle":angle,"handle":handle,"body":body,"feet":feet,"leg_height":leg_height}

func _pusher(offset: Vector2, body: Dictionary, feet: Array) -> void:
	var hip: Vector2 = body.hip
	for i: int in feet.size():
		var foot: Vector2 = feet[i]-offset
		var origin := hip+Vector2(3 if i==0 else -3,0)
		var knee := origin.lerp(foot,.48)+Vector2(6,-1)
		_segment(_part("thigh"),origin,knee,15)
		var shin := asset(_part("shin"))
		if shin!=null:
			var shoe_height := shin.get_height()*5.0/17.0
			var ankle := foot-Vector2(0,7)
			var v := ankle-knee
			_view_transform(knee.round(),v.angle()-PI*.5)
			draw_texture_rect_region(shin,Rect2(-7,-2,14,v.length()+4),Rect2(0,0,shin.get_width(),shin.get_height()-shoe_height))
			_view_transform(Vector2.ZERO)
			draw_texture_rect_region(shin,Rect2((foot-Vector2(7,10)).round(),Vector2(_display_size(shin,34).x,10)),Rect2(0,shin.get_height()-shoe_height,shin.get_width(),shoe_height))
	_view_transform(body.origin,float(body.angle))
	var reference: Texture2D = body.texture
	var region := Rect2(0,0,reference.get_width(),float(body.cut_y))
	draw_texture_rect_region(reference,Rect2(Vector2.ZERO,region.size*float(body.scale)),region)
	_view_transform(Vector2.ZERO)
