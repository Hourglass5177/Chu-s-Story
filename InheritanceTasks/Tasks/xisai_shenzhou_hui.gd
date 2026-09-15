extends HeritageStageTask

const Route := preload("res://InheritanceTasks/Data/shenzhou_escort_route.gd")
var distance: float = 0.0
var speed: float = 200.0
var target_speed: float = 200.0
var lane: float = 1.0
var target_lane: int = 1
var recovery: float = 0.0
var recovery_safe_until: float = 0.0
var collisions: int = 0
var obstacles: Array[Dictionary] = []
var _lesson_left: bool = false
var _lesson_right: bool = false
var _lesson_slowed: bool = false
var wake_distance: float = 0.0

func input_profile_kind() -> StringName: return &"escort"
func play_feedback(good: bool) -> void:
	if is_instance_valid(sfx): sfx.stream = load("res://InheritanceTasks/Audio/action-story-v3/boat-%s.wav"%("good" if good else "miss"))
	super.play_feedback(good)
	if is_instance_valid(sfx):
		sfx.pitch_scale = 1.0
		sfx.volume_db = -15.0

func tutorial_version() -> int: return 4

func setup_game() -> void:
	duration_seconds = 35.0
	distance = 0.0
	speed = 200.0
	target_speed = 200.0
	lane = 1.0
	target_lane = 1
	recovery = 0.0
	recovery_safe_until = 0.0
	collisions = 0
	wake_distance = 0.0
	obstacles = Route.obstacles()
	_lesson_left = false
	_lesson_right = false
	_lesson_slowed = false
	lesson_text = "左右换道，上下调速"
	status_text = "护送神舟，避开前方船只"

func begin_game() -> void: setup_game()
func practice_tick(delta: float) -> void: step_game(delta)

func demo_tick(delta: float) -> void:
	target_lane = 0 if phase_time < 1.1 else 1
	target_speed = Route.MIN_SPEED if phase_time >= 1.5 else 200.0
	advance_boat(delta,false)

func practice_edge(direction: int, down: bool) -> void: game_edge(direction,down)

func game_edge(direction: int, down: bool) -> void:
	if not down or recovery > 0.0: return
	if direction in [-1,1]:
		target_lane = clampi(target_lane+direction,0,2)
		if direction < 0: _lesson_left = true
		if direction > 0: _lesson_right = true
	if direction == -2: target_speed = Route.MAX_SPEED
	if direction == 2: target_speed = Route.MIN_SPEED

func task_gui_input(event: InputEvent) -> bool:
	if not is_input_active() or resume_countdown > 0.0: return false
	if event is InputEventMouseMotion:
		if input_profile != null: input_profile.note_pointer_motion(event.relative)
		return false
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			var stepped_speed := clampf(target_speed+(25.0 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -25.0),Route.MIN_SPEED,Route.MAX_SPEED)
			if input_profile != null:
				input_profile.pointer_edge(-2 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 2,true,event.button_index)
				input_profile.pointer_edge(-2 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 2,false,event.button_index)
			target_speed = stepped_speed
			return true
		if event.button_index == MOUSE_BUTTON_LEFT:
			var point := logical_point(event.position)
			if not Rect2(80,100,840,460).has_point(point): return false
			var selected := clampi(int((point.x-80)/280.0),0,2)
			var direction := signi(selected-target_lane)
			if direction != 0 and input_profile != null: input_profile.pointer_edge(direction,event.pressed)
			elif not event.pressed and input_profile != null: input_profile.release_pointer(event)
			return true
	return false

func advance_boat(delta: float, check_collision: bool = true) -> void:
	if recovery > 0.0:
		recovery = maxf(0.0,recovery-delta)
		return
	var previous := Vector2(lane,distance)
	speed = move_toward(speed,target_speed,(Route.DECELERATION if speed>target_speed else Route.ACCELERATION)*delta)
	lane = move_toward(lane,float(target_lane),delta/Route.LANE_SECONDS)
	distance += speed*delta
	wake_distance += speed*delta
	if check_collision and distance >= recovery_safe_until:
		for obstacle: Dictionary in obstacles:
			if Route.swept_hit(previous,Vector2(lane,distance),obstacle):
				collisions += 1
				recovery = .7
				speed = Route.MIN_SPEED
				target_speed = Route.MIN_SPEED
				# Recover in front of the obstruction. Never award forward route
				# distance for a collision: intentionally crashing must cost time.
				distance = maxf(0.0,minf(distance,float(obstacle.distance)-Route.COLLISION_HALF_LENGTH-220.0))
				recovery_safe_until = distance+100.0
				# Leave enough approach distance to choose again, but do not move
				# automatically into the clear lane: that made crashes bypass the
				# two braking passages. The nearest current lane stays predictable.
				lane = roundf(lane)
				target_lane = roundi(lane)
				play_feedback(false)
				break

func step_game(delta: float) -> void:
	advance_boat(delta,phase==Phase.LIVE)
	var narrow := Route.approaching_turn(distance)
	status_text = "前方换道 · 减速可多留观察时间" if narrow else ("扶稳后继续" if recovery>0 else "看前方，提早换道")
	if phase == Phase.PRACTICE:
		if speed < Route.MIN_SPEED+5.0: _lesson_slowed = true
		lesson_text = "向两边各换一次道" if not (_lesson_left and _lesson_right) else "减速，让水纹慢下来"
		if _lesson_left and _lesson_right and _lesson_slowed and is_equal_approx(lane,float(target_lane)):
			finish_lesson()
		return
	set_progress(distance/Route.LENGTH)
	if phase==Phase.LIVE and distance>=Route.LENGTH:
		complete_success({"collisions":collisions,"escort_version":3},"神舟平安远去")

func on_time_expired() -> void:
	complete_failure(&"escort_unfinished","提前看空道，来不及时先减速",{"collisions":collisions,"distance":distance})

func get_presentation_state() -> Dictionary:
	var visible: Array[Dictionary] = []
	for obstacle: Dictionary in obstacles:
		var gap := float(obstacle.distance)-distance
		if gap >= -140.0 and gap <= 1000.0:
			var item := obstacle.duplicate()
			item["gap"] = gap
			visible.append(item)
	return {"lane":lane,"target_lane":target_lane,"speed":speed,"target_speed":target_speed,"max_speed":Route.MAX_SPEED,"distance":distance,"route_length":Route.LENGTH,"recovery":recovery,"obstacles":visible,"narrow":Route.approaching_turn(distance),"wake_distance":wake_distance,"action":&"miss" if recovery>0 else &"ready"}

func draw_scene() -> void:
	draw_rect(Rect2(Vector2.ZERO,STAGE),Color("759f9e"))
	for x: int in [360,640]: draw_line(Vector2(x,110),Vector2(x,580),Color("accbc0"),3)
	for obstacle: Dictionary in get_presentation_state().obstacles:
		var at := Vector2(220+int(obstacle.lane)*280,450-float(obstacle.gap)*.39)
		draw_rect(Rect2(at-Vector2(45,22),Vector2(90,44)),Color("684c37"))
	var at := Vector2(220+lane*280,450)
	draw_rect(Rect2(at-Vector2(48,60),Vector2(96,90)),RED)
	draw_rect(Rect2(at-Vector2(28,99),Vector2(56,65)),GOLD)

func draw_pixel_overlay() -> void:
	draw_rect(Rect2(810,496,132,60),Color("384f4b"))
	label_at(Vector2(829,523),"%d" % roundi(speed),24,PAPER)
	label_at(Vector2(829,548),"航速",20,PAPER)
