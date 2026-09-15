extends HeritageStageTask

func feedback_overlay_bounds() -> Rect2:
	return Rect2(390, 38, 400, 50)

func tutorial_overlay_bounds() -> Rect2:
	return Rect2(35, 475, 930, 105)

var heat: float = 0.35
var velocity: float = 0.0
var target: float = 0.5
var brew: float = 0.10
var lesson_caught: bool = false
var lesson_released: bool = false
var lesson_steady: float = 0.0
const TARGET_KEYS: Array[Vector2] = [Vector2(0,0.42),Vector2(2,0.42),Vector2(5,0.62),Vector2(8,0.37),Vector2(11,0.70),Vector2(14,0.51),Vector2(16,0.65),Vector2(18,0.43),Vector2(20,0.64),Vector2(22,0.50),Vector2(25,0.58)]

func input_profile_kind() -> StringName:
	return &"heat"

func tutorial_version() -> int:
	return 4

func setup_game() -> void:
	duration_seconds = 25
	lesson_text = "按住添火，松开收火"
	heat = 0.35
	velocity = 0
	target = 0.42
	brew = 0.10
	lesson_caught = false
	lesson_released = false
	lesson_steady = 0.0

func begin_game() -> void:
	heat = 0.35
	velocity = 0.0
	target = target_at(0.0)
	brew = 0.10

func begin_practice() -> void:
	heat = 0.18
	velocity = 0.0
	target = 0.48
	lesson_text = "按住，追上金区"

func target_at(t: float) -> float:
	for i: int in range(1,TARGET_KEYS.size()):
		if t <= TARGET_KEYS[i].x:
			var a: Vector2 = TARGET_KEYS[i-1]
			var b: Vector2 = TARGET_KEYS[i]
			return lerpf(a.y,b.y,smoothstep(a.x,b.x,t))
	return TARGET_KEYS[-1].y

func practice_tick(delta: float) -> void:
	advance_heat(delta)
	if not lesson_caught:
		lesson_steady = lesson_steady + delta if pressed[0] and absf(heat-target) <= 0.075 else 0.0
		if lesson_steady >= 0.22:
			lesson_caught = true
			lesson_steady = 0.0
			lesson_text = "松开，让火候停下来"
	elif lesson_released:
		lesson_steady = lesson_steady + delta if velocity <= 0.0 and absf(heat-target) <= 0.09 else 0.0
		if lesson_steady >= 0.10: finish_lesson()
		elif heat < target - 0.09:
			lesson_text = "再添一点火，追上后松开"

func demo_tick(delta: float) -> void:
	pressed[0] = phase_time < 1.2
	advance_heat(delta)

func practice_edge(_direction: int, down: bool) -> void:
	if lesson_caught:
		lesson_released = not down
		lesson_steady = 0.0

func advance_heat(delta: float) -> void:
	var hold: bool = bool(pressed[0])
	velocity = move_toward(velocity,0.28 if hold else -0.22,delta*1.35)
	heat = clampf(heat+velocity*delta,0,1)
	if heat<=0 or heat>=1: velocity=0

func step_game(delta: float) -> void:
	target = target_at(game_time)
	advance_heat(delta)
	var inside: bool = absf(heat-target)<=0.075
	brew = clampf(brew+delta*(0.055 if inside else -0.035),0,1)
	set_progress(brew)
	status_text = "火候合适" if inside else ("添一点火" if heat<target else "收一收火")

func on_time_expired() -> void:
	if brew>=0.70: complete_success({"brew":brew,"heat_version":3},"这一炉成了")
	else: complete_failure(&"heat_unsteady","火候还需守稳",{"brew":brew,"heat_version":3})

func draw_scene() -> void:
	hills()
	person(Vector2(290,420),TEAL,0.6 if pressed[0] else 0.0)
	draw_circle(Vector2(510,365),90,INK)
	draw_rect(Rect2(435,270,150,65),INK)
	draw_line(Vector2(420,268),Vector2(600,268),GOLD,8)
	draw_circle(Vector2(510,380),48,RED.lerp(GOLD,heat))
	for i: int in 4:
		var x: float = 472+i*24
		draw_colored_polygon(PackedVector2Array([Vector2(x-14,480),Vector2(x,440-heat*55-sin(game_time*10+i)*9),Vector2(x+14,480)]),GOLD)
		draw_circle(Vector2(480+i*22,245-fmod(game_time*28+i*30,90)),12+i*3,Color(0.3,0.35,0.35,0.15+heat*0.2))
	draw_rect(Rect2(735,140,60,350),INK)
	draw_rect(Rect2(733,490-(target+0.075)*350,64,350*0.15),GOLD)
	draw_line(Vector2(720,490-heat*350),Vector2(810,490-heat*350),RED,8)
	var future: float = target_at(game_time+0.65)-target
	label_at(Vector2(745,118),"↑" if future>0.01 else ("↓" if future < -0.01 else "稳"),26)
	draw_rect(Rect2(180,535,600,18),INK)
	draw_rect(Rect2(180,535,600*brew,18),GOLD)
	draw_line(Vector2(600,525),Vector2(600,565),RED,3)
	label_at(Vector2(790,551),"七成成炉",20)

func get_visual_state() -> Dictionary:
	var state := super.get_visual_state()
	state.heat = heat
	state.target = target
	state.target_low = target - 0.075
	state.target_high = target + 0.075
	state.brew = brew
	state.held = bool(pressed[0])
	state.heat_velocity = velocity
	state.target_trend = target_at(game_time + 0.65) - target
	state.lesson_caught = lesson_caught
	state.lesson_released = lesson_released
	state.action = &"action" if pressed[0] else (&"miss" if heat > target + 0.15 else &"release")
	if run_state == RunState.FINISHED:
		var art: Resource = context.metadata.get(&"presentation") if context != null else null
		state.action = (&"success" if art != null and int(art.get("version")) >= 2 else &"recover") if brew >= .7 else &"miss"
	return state

func draw_pixel_overlay() -> void:
	var art: Resource = context.metadata.get(&"presentation") if context != null else null
	if art != null and int(art.get("version")) >= 2: return
	draw_rect(Rect2(835,145,90,350),Color("322e29"))
	draw_rect(Rect2(849,162,42,306),Color("594b3f"))
	draw_rect(Rect2(847,468-(target+.075)*306,46,.15*306),GOLD)
	draw_line(Vector2(835,468-heat*306),Vector2(905,468-heat*306),Color("fff2cc"),6)
	label_at(Vector2(840,126),"火候",25,PAPER)
	var future: float = target_at(game_time+.65)-target
	label_at(Vector2(897,468-target*306+8),"↑" if future>.01 else ("↓" if future<-.01 else "稳"),24,GOLD)
	draw_rect(Rect2(100,520,810,62),Color(.15,.13,.11,.9))
	label_at(Vector2(119,545),"炼制",20,PAPER)
	draw_rect(Rect2(185,536,590,20),Color("635141"))
	draw_rect(Rect2(185,536,590*brew,20),GOLD)
	draw_line(Vector2(598,530),Vector2(598,563),PAPER,3)
	label_at(Vector2(790,553),"七成成炉",20,PAPER)
