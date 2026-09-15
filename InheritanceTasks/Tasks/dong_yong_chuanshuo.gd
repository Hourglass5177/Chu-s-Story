extends HeritageStageTask

# A single axle handcart. The road drives both contact and rendering.
const ROAD: Array[Vector2] = [Vector2(0,440),Vector2(420,440),Vector2(930,350),Vector2(1150,350),Vector2(1580,450),Vector2(1660,450),Vector2(2040,450),Vector2(2440,374),Vector2(2740,420),Vector2(3390,420)]
const BRIDGE_START: float = 1660.0
const BRIDGE_END: float = 2040.0
const CART_HALF_LENGTH: float = 65.0
const SAFE_SPEED: float = 100.0
const MAX_SPEED: float = 165.0
const BRAKE_DECELERATION: float = 235.0
const GOAL_DISTANCE: float = 3320.0
const WHEEL_RADIUS: float = 24.0
const PUSHER_OFFSET: float = 180.0
var distance: float = 20.0
var speed: float = 0.0
var recovery: float = 0.0
var mistakes: int = 0
var pose: StringName = &"idle"
var road_slope: float = 0.0
var stability: float = 1.0
var bridge_warning: bool = false
var braking_distance: float = 0.0
var bridge_distance: float = 0.0
var _practiced_push: bool = false
var wheel_travel: float = 0.0
var contact: Dictionary = {}
var _safe_position: float = 20.0

func input_profile_kind() -> StringName: return &"cart"
func play_feedback(good: bool) -> void:
	if is_instance_valid(sfx): sfx.stream = load("res://InheritanceTasks/Audio/action-story-v3/cart-%s.wav"%("good" if good else "miss"))
	super.play_feedback(good)
	if is_instance_valid(sfx):
		sfx.pitch_scale = 1.0
		sfx.volume_db = -17.0

func tutorial_version() -> int: return 4

func setup_game() -> void:
	duration_seconds = 30.0
	lesson_text = "右侧推车；左侧刹到停稳"
	distance = 20.0
	speed = 0.0
	recovery = 0.0
	mistakes = 0
	wheel_travel = 0.0
	_safe_position = 20.0
	_practiced_push = false
	pose = &"idle"
	_update_contact()

func begin_game() -> void: setup_game()
func practice_tick(delta: float) -> void: step_game(delta)
func practice_edge(_direction: int, _down: bool) -> void: pass
func pointer_direction(point: Vector2) -> int: return -1 if point.x < 500 else 1

func task_gui_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
		if not is_input_active() or resume_countdown > 0: return false
		input_profile.pointer_edge(1 if event.button_index==MOUSE_BUTTON_LEFT else -1,event.pressed,event.button_index)
		return true
	return super.task_gui_input(event)

func demo_tick(delta: float) -> void:
	pressed[1] = phase_time < 1.35
	pressed[-1] = phase_time >= 1.35
	step_game(delta)

func height_at(x: float) -> float:
	for i: int in range(1,ROAD.size()):
		if x <= ROAD[i].x:
			var t := clampf(inverse_lerp(ROAD[i-1].x,ROAD[i].x,x),0.0,1.0)
			return lerpf(ROAD[i-1].y,ROAD[i].y,t*t*(3.0-2.0*t))
	return ROAD[-1].y

func slope_at(x: float) -> float:
	return (height_at(x+1.0)-height_at(x-1.0))*.5

func step_game(delta: float) -> void:
	if recovery > 0.0:
		recovery = maxf(0.0,recovery-delta)
		pose = &"recover"
		_update_contact()
		return
	road_slope = slope_at(distance)
	var brake := bool(pressed.get(-1,false))
	var push := bool(pressed.get(1,false)) or bool(pressed.get(0,false))
	var push_strength := input_profile.action_value(&"push") if input_profile != null else 0.0
	var brake_strength := input_profile.action_value(&"brake") if input_profile != null else 0.0
	if push and push_strength <= 0.0: push_strength = 1.0
	if brake and brake_strength <= 0.0: brake_strength = 1.0
	var old_distance := distance
	if brake: speed = move_toward(speed,0.0,BRAKE_DECELERATION*brake_strength*delta)
	else: speed = clampf(speed+(130.0*push_strength+road_slope*220.0-28.0)*delta,0.0,MAX_SPEED)
	distance += speed*delta
	wheel_travel += Vector2(distance-old_distance,height_at(distance)-height_at(old_distance)).length()
	bridge_distance = BRIDGE_START-CART_HALF_LENGTH-distance
	braking_distance = maxf(0.0,(speed*speed-SAFE_SPEED*SAFE_SPEED)/(2.0*BRAKE_DECELERATION))
	bridge_warning = distance >= 1210.0 and distance-CART_HALF_LENGTH < BRIDGE_END
	var on_bridge := distance+CART_HALF_LENGTH >= BRIDGE_START and distance-CART_HALF_LENGTH <= BRIDGE_END
	stability = clampf(1.0-maxf(0.0,speed-SAFE_SPEED)/65.0,0.0,1.0) if bridge_warning else 1.0
	if on_bridge and speed > SAFE_SPEED:
		distance = BRIDGE_START-CART_HALF_LENGTH-90.0
		speed = 0.0
		recovery = .7
		mistakes += 1
		play_feedback(false)
		pose = &"steady"
		status_text = "扶稳了 · 桥上放慢"
	else:
		_safe_position = distance
		pose = &"brake" if brake and speed>1.0 else (&"stop" if brake else (&"push_uphill" if push and road_slope < -.05 else (&"push" if push else (&"coast" if speed>1.0 else &"idle"))))
		status_text = "桥上慢行" if on_bridge else ("桥前减速" if bridge_warning else ("上坡用力" if road_slope < -.05 else ("下坡收力" if road_slope > .05 else "推车向前")))
	_update_contact()
	if phase == Phase.PRACTICE:
		if push and not brake and speed >= 65.0: _practiced_push = true
		lesson_text = "刹到停稳" if _practiced_push else "按住推车，让车轮转起来"
		if _practiced_push and brake and speed <= 10.0:
			finish_lesson()
			return
	set_progress(distance/GOAL_DISTANCE)
	if phase == Phase.LIVE and distance >= GOAL_DISTANCE:
		pose = &"arrive"
		complete_success({"stops":mistakes,"route_version":3},"平稳到达")

func _foot(phase_offset: float) -> Vector2:
	var travel := maxf(0.0,wheel_travel)
	var cycle := floorf(travel/72.0+phase_offset)
	var phase_position := fposmod(travel/72.0+phase_offset,1.0)
	var relative_plant := (cycle-phase_offset)*72.0-travel+16.0
	var x := distance-PUSHER_OFFSET+relative_plant
	var lift := 0.0
	if phase_position > .55:
		var t := (phase_position-.55)/.45
		x += 72.0*smoothstep(0.0,1.0,t)
		lift = sin(t*PI)*10.0
	if speed < 1.0: lift = 0.0
	return Vector2(x,height_at(x)-lift)

func _update_contact() -> void:
	var axle := Vector2(distance,height_at(distance)-WHEEL_RADIUS)
	var body_x := distance-PUSHER_OFFSET
	var ground := height_at(body_x)
	var desired_hand_y := ground-70.0
	var handle_local := Vector2(-153.0,-31.0)
	var angle := atan(slope_at(distance))
	# Newton solve the single-axle cart's handle height. This permits body and
	# wheel to straddle a crest without rotating the pusher into the road.
	for i: int in 5:
		var local := handle_local.rotated(angle)
		var error := axle.y+local.y-desired_hand_y
		angle = clampf(angle-error/minf(-40.0,local.x),-.65,.65)
	var handle := axle+handle_local.rotated(angle)
	var lean := 8.0 if pose in [&"push",&"push_uphill"] else (-7.0 if pose==&"brake" else 0.0)
	var bounce := 1.5*sin(wheel_travel/72.0*TAU*2.0) if speed>1.0 else 0.0
	var hip := Vector2(body_x,ground-38.0+bounce)
	var shoulder := Vector2(body_x+lean,ground-89.0+bounce)
	var reach := handle-shoulder
	var half_length := reach.length()*.5
	var arm_length := maxf(29.0,half_length+1.0)
	var elbow := (shoulder+handle)*.5+Vector2(-reach.y,reach.x).normalized()*sqrt(maxf(0.0,arm_length*arm_length-half_length*half_length))
	contact = {"axle":axle,"cart_angle":angle,"handle":handle,"feet":[_foot(0.0),_foot(.5)],"hip":hip,"shoulder":shoulder,"elbow":elbow}

func get_presentation_state() -> Dictionary:
	var state := {"pose":pose,"distance":distance,"speed":speed,"max_speed":MAX_SPEED,"safe_speed":SAFE_SPEED,"slope":road_slope,"height":height_at(distance),"stability":stability,"bridge_warning":bridge_warning,"bridge_distance":bridge_distance,"braking_distance":braking_distance,"recovery":recovery,"road":ROAD,"bridge_start":BRIDGE_START,"bridge_end":BRIDGE_END,"wheel_angle":wheel_travel/WHEEL_RADIUS,"push":bool(pressed.get(1,false)),"brake":bool(pressed.get(-1,false))}
	state.merge(contact,true)
	var samples := PackedVector2Array()
	for x: int in range(-200,3401,10): samples.append(Vector2(x,height_at(x)))
	state["road_samples"] = samples
	return state

func on_time_expired() -> void: complete_failure(&"road_unfinished","桥前早一点减速",{"stops":mistakes})

func draw_scene() -> void:
	if contact.is_empty(): return
	var camera := maxf(0.0,distance-370.0)
	hills(camera*.12)
	var previous := Vector2(-200-camera,height_at(-200))
	for x: int in range(-190,3401,10):
		var next := Vector2(x-camera,height_at(x))
		draw_colored_polygon(PackedVector2Array([previous,next,Vector2(next.x,600),Vector2(previous.x,600)]),Color("8c7854"))
		previous = next
	var axle: Vector2 = contact.axle-Vector2(camera,0)
	draw_arc(axle,WHEEL_RADIUS,0,TAU,24,INK,5)
	draw_line(axle,axle+Vector2(0,-WHEEL_RADIUS).rotated(wheel_travel/WHEEL_RADIUS),GOLD,3)
	var hand: Vector2 = contact.handle-Vector2(camera,0)
	draw_line(hand,axle+Vector2(40,-31).rotated(contact.cart_angle),RED,10)
	person(axle+Vector2(18,-45),GOLD)
	var hip: Vector2 = contact.hip-Vector2(camera,0)
	var shoulder: Vector2 = contact.shoulder-Vector2(camera,0)
	for foot: Vector2 in contact.feet: draw_line(hip,foot-Vector2(camera,0),TEAL,10)
	draw_line(hip,shoulder,TEAL,25)
	draw_circle(shoulder+Vector2(0,-19),15,Color("d4ac82"))
	draw_polyline(PackedVector2Array([shoulder,contact.elbow-Vector2(camera,0),hand]),TEAL,10)

func draw_pixel_overlay() -> void:
	if bridge_warning:
		draw_rect(Rect2(752,32,218,88),Color("ead8ae"))
		draw_rect(Rect2(752,32,218,88),Color("77543a"),false,3)
		label_at(Vector2(772,62),"桥上慢行",24,INK)
		draw_rect(Rect2(774,82,172,12),Color("4b3a2b"))
		draw_rect(Rect2(774,82,172*SAFE_SPEED/MAX_SPEED,12),TEAL)
		draw_line(Vector2(774+172*speed/MAX_SPEED,77),Vector2(774+172*speed/MAX_SPEED,100),Color("c57735"),4)
