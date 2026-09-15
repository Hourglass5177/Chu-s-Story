extends HeritageStageTask

const AUDIO: String = "res://arts/非遗媒体资源/数字版/2026-09-09/xingshan-xiatianhaozi-v1.ogg"
var clock: HeritageMusicClock
var bird_y: float=300
var vertical_speed: float=0
var gates: Array[Dictionary]=[]
var hits: int=0
var recovery: float=0
var stall: float=0
var previous_time: float=0

# Presentation-only samples; never read by movement, gate judgment or music.
const FOLLOWER_DELAYS: Array[float] = [0.18,0.34,0.50]
const FOLLOWER_OFFSETS: Array[Vector2] = [Vector2(-60,40),Vector2(-95,56),Vector2(-130,72)]
const FOLLOWER_WING_OFFSETS: Array[float] = [0.0,0.085,0.17]
var _flock_history: Array[Dictionary] = []
var _flock_time: float = 0.0
var _flock_frozen: Array[Dictionary] = []
var _flock_frozen_active: bool = false

func setup_game() -> void:
	duration_seconds=42.3
	lesson_text="按下振翅，按住滑翔，松开下降；试着飞过山口。"
	if not ResourceLoader.exists(AUDIO):
		complete_technical_error(&"missing_audio","山歌原声未就绪")
		return
	if clock==null:
		clock=HeritageMusicClock.new()
		add_child(clock)
	bird_y=300
	vertical_speed=0
	gates.clear()
	hits=0
	recovery=0
	for i: int in 16:
		gates.append({"time":3.5+i*2.35,"y":290+sin(i*1.35)*135,"done":false,"hit":false})
	_reset_flock_history()

func begin_game() -> void:
	_reset_flock_history()
	clock.begin(load(AUDIO) as AudioStream)
	previous_time=0
	stall=0

func task_tick(delta: float) -> void:
	if phase!=Phase.LIVE or resume_countdown>0:
		super.task_tick(delta)
		return
	var now: float=clock.seconds()
	stall=stall+delta if now<=previous_time+0.00001 else 0.0
	previous_time=now
	if stall>2.0 or (not clock.playing and now<duration_seconds-0.35):
		complete_technical_error(&"audio_playback_failed","山歌播放中断")
		return
	game_time=now
	accumulator+=minf(delta,0.25)
	while accumulator>=1.0/120.0:
		accumulator-=1.0/120.0
		move_bird(1.0/120.0)
	for gate: Dictionary in gates:
		if not gate.done and game_time>=float(gate.time):
			gate.done=true
			gate["error"] = bird_y-float(gate.y)
			gate.hit=absf(bird_y-float(gate.y))<=78
			if gate.hit: hits+=1
			else:
				recovery=0.65
				bird_y=clampf(float(gate.y),130,440)
				vertical_speed=0
			play_feedback(gate.hit)
	# Include the existing collision recovery teleport at the current sample time.
	_record_flock_sample()
	set_progress(hits/16.0)
	time_left=maxf(0,duration_seconds-game_time)
	if not clock.playing and game_time>=duration_seconds-0.35: on_time_expired()
	elif game_time>duration_seconds+0.5: complete_technical_error(&"audio_duration_mismatch","山歌时长不一致")

func game_edge(_direction: int, down: bool) -> void:
	if down and recovery<=0: vertical_speed=-220

func practice_edge(direction: int, down: bool) -> void:
	game_edge(direction,down)
	if not down and lesson_edges>=3: finish_lesson()

func practice_tick(delta: float) -> void: move_bird(delta)

func demo_tick(delta: float) -> void:
	pressed[0] = phase_time < 1.2
	if phase_time < 0.1: vertical_speed = -180
	move_bird(delta)

func move_bird(delta: float) -> void:
	recovery=maxf(0,recovery-delta)
	vertical_speed+=260*delta
	if pressed[0]: vertical_speed=clampf(vertical_speed,-130,45)
	bird_y=clampf(bird_y+vertical_speed*delta,100,480)
	if bird_y<=100 or bird_y>=480: vertical_speed=0
	_advance_flock(delta)

func _flock_sample(at: float) -> Dictionary:
	return {"time":at,"y":bird_y,"speed":vertical_speed,"recovery":recovery,"held":bool(pressed[0])}

func _reset_flock_history() -> void:
	_flock_time = 0.0
	_flock_history.clear()
	_flock_frozen.clear()
	_flock_frozen_active = false
	_record_flock_sample()

func _record_flock_sample() -> void:
	var sample := _flock_sample(_flock_time)
	if not _flock_history.is_empty() and is_equal_approx(float(_flock_history[-1].time),_flock_time):
		_flock_history[-1] = sample
	else:
		_flock_history.append(sample)
	# Retain one sample before the longest delay for interpolation.
	while _flock_history.size()>2 and float(_flock_history[1].time)<_flock_time-0.60:
		_flock_history.pop_front()

func _advance_flock(delta: float) -> void:
	if _flock_frozen_active:
		# Old temporal history was cleared at pause. Seed only the three frozen
		# visible poses, so resuming does not snap all birds to the leader.
		for i: int in range(_flock_frozen.size()-1,-1,-1):
			var sample: Dictionary = (_flock_frozen[i].sample as Dictionary).duplicate()
			sample.time = _flock_time-FOLLOWER_DELAYS[i]
			_flock_history.append(sample)
		_record_flock_sample()
		_flock_frozen.clear()
		_flock_frozen_active = false
	_flock_time += delta
	_record_flock_sample()

func _sample_flock_history(at: float) -> Dictionary:
	if _flock_history.is_empty(): return _flock_sample(at)
	if at<=float(_flock_history[0].time): return _flock_history[0].duplicate()
	for i: int in range(1,_flock_history.size()):
		var after: Dictionary = _flock_history[i]
		if at>float(after.time): continue
		var before: Dictionary = _flock_history[i-1]
		var blend := inverse_lerp(float(before.time),float(after.time),at)
		# Position is continuous. Input/recovery states switch at their timestamp
		# instead of anticipating a collision by interpolating a boolean/state.
		var sample: Dictionary = (after if blend>=0.999999 else before).duplicate()
		sample.y = lerpf(float(before.y),float(after.y),blend)
		sample.speed = lerpf(float(before.speed),float(after.speed),blend)
		return sample
	return _flock_history[-1].duplicate()

func get_follower_states() -> Array[Dictionary]:
	if _flock_frozen_active: return _flock_frozen.duplicate(true)
	var followers: Array[Dictionary] = []
	for i: int in FOLLOWER_DELAYS.size():
		var sample := _sample_flock_history(_flock_time-FOLLOWER_DELAYS[i])
		var r := float(sample.recovery)
		var pose := "miss" if r>0.35 else ("recover" if r>0 else ("flap" if bool(sample.held) and float(sample.speed)<-20 else ("glide" if bool(sample.held) else "descend")))
		followers.append({"position":Vector2(280,float(sample.y))+FOLLOWER_OFFSETS[i],
			"pose":pose,"recovery":r,"delay":FOLLOWER_DELAYS[i],"sample":sample,
			"wing_time":_flock_time-FOLLOWER_DELAYS[i]+FOLLOWER_WING_OFFSETS[i]})
	return followers

func on_suspension_changed(suspended: bool) -> void:
	if suspended and not _flock_frozen_active:
		_flock_frozen = get_follower_states()
		_flock_history.clear()
		_flock_frozen_active = true
	super.on_suspension_changed(suspended)

func pause_media(value: bool) -> void:
	if is_instance_valid(clock): clock.freeze(value)
func stop_media() -> void:
	if is_instance_valid(clock): clock.stop()

func on_time_expired() -> void:
	var errors: Array[float] = []
	for gate: Dictionary in gates: errors.append(float(gate.get("error",0)))
	if hits>=12: complete_success({"gates":hits,"total":16,"gate_errors":errors},"山歌飞过山岭")
	else: complete_failure(&"gates_missed","再顺着乐句飞一次",{"gates":hits,"total":16,"gate_errors":errors})

func get_presentation_state() -> Dictionary:
	var bird_pose := "miss" if recovery>0.35 else ("recover" if recovery>0 else ("flap" if pressed[0] and vertical_speed < -20 else ("glide" if pressed[0] else "descend")))
	return {"bird_y":bird_y,"vertical_speed":vertical_speed,"bird_pose":bird_pose,
		"music_time":game_time,"gates":gates,"recovery":recovery,"hits":hits,"held":bool(pressed[0]),
		"followers":get_follower_states()}

func draw_pixel_overlay() -> void:
	draw_rect(Rect2(250,526,640,48),Color(.1,.16,.15,.9))
	label_at(Vector2(269,560),"按下振翅 · 按住滑翔 · 松开下降",24,PAPER)
	draw_rect(Rect2(749,43,233,52),Color(.1,.16,.15,.9))
	label_at(Vector2(763,79),"山口 %d / 16"%hits,30,PAPER)

func draw_scene() -> void:
	hills(game_time*24)
	for gate: Dictionary in gates:
		var x: float=280+(float(gate.time)-game_time)*160
		if x < -80 or x>1100: continue
		var y: float=gate.y
		draw_colored_polygon(PackedVector2Array([Vector2(x-70,490),Vector2(x,y+90),Vector2(x+70,490)]),TEAL)
		draw_colored_polygon(PackedVector2Array([Vector2(x-65,80),Vector2(x,y-90),Vector2(x+65,80)]),Color("8eaa91"))
		draw_arc(Vector2(x,y),35,-PI*0.5,PI*0.5,20,GOLD,4)
	var wing: float=sin(game_time*13)*16 if pressed[0] else 5
	var bird:=Vector2(280,bird_y)
	draw_colored_polygon(PackedVector2Array([bird+Vector2(-24,2),bird+Vector2(-4,-12-wing),bird+Vector2(28,0),bird+Vector2(0,9)]),RED if recovery>0 else INK)
	draw_line(bird,bird+Vector2(-15,22+wing),INK,5)
	for follower: Dictionary in get_follower_states():
		var p: Vector2 = follower.position
		var spread := 4.0 if reduced_motion else sin(float(follower.wing_time)*TAU*4.5)*7.0
		var color := RED if float(follower.recovery)>0.35 else TEAL
		draw_line(p+Vector2(-12,-spread),p,color,3)
		draw_line(p,p+Vector2(12,-spread),color,3)
	label_at(Vector2(320,550),"《下田号子》 · 飞鸟过岭为游戏化表现",20)
