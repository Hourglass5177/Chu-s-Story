extends HeritageStageTask

enum Blow { READY, INFLATE, RESIDUAL, RESULT }
const TARGETS: Array[Vector2] = [Vector2(0.56,0.70),Vector2(0.66,0.80),Vector2(0.59,0.73)]
var blow_phase: Blow = Blow.READY
var trial: int = 0
var radius: float = 0.0
var pressure: float = 0.0
var residual: float = 0.0
var stage_time: float = 0.0
var successes: int = 0
var outcomes: Array[String] = []
var outcome_radii: Array[float] = []
var breath: AudioStreamPlayer
var rejoin_grace: float = 0.0

func setup_game() -> void:
	if breath == null:
		breath = AudioStreamPlayer.new()
		add_child(breath)
		var wind := load("res://InheritanceTasks/Audio/breath-feedback.wav") as AudioStreamWAV
		if wind != null:
			wind = wind.duplicate() as AudioStreamWAV
			wind.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wind.loop_end = 44100
			breath.stream = wind
	duration_seconds=25
	lesson_text="按住吹气；接近虚线时提前松开，观察余胀。"
	blow_phase=Blow.READY
	trial=0
	radius=0
	pressure=0
	residual=0
	stage_time=0
	successes=0
	outcomes.clear()
	outcome_radii.clear()
	rejoin_grace = 0.0

func practice_edge(_direction: int, down: bool) -> void:
	game_edge(0,down)

func practice_tick(delta: float) -> void:
	advance_blow(delta)
	if blow_phase==Blow.RESULT and stage_time>0.9: finish_lesson()

func demo_tick(delta: float) -> void:
	if blow_phase == Blow.READY:
		radius = 0.45
		game_edge(0, true)
	if phase_time > 1.5 and blow_phase == Blow.INFLATE: game_edge(0, false)
	advance_blow(delta)

func game_edge(_direction: int, down: bool) -> void:
	if down and blow_phase==Blow.READY:
		blow_phase=Blow.INFLATE
		stage_time=0
	elif not down and blow_phase==Blow.INFLATE:
		blow_phase=Blow.RESIDUAL
		residual=0
		stage_time=0

func step_game(delta: float) -> void:
	advance_blow(delta)
	if blow_phase==Blow.RESULT and stage_time>1.15:
		trial+=1
		if trial>=3: on_time_expired(); return
		radius=0
		pressure=0
		blow_phase=Blow.READY
		stage_time=0

func advance_blow(delta: float) -> void:
	if rejoin_grace > 0.0:
		if pressed[0]: rejoin_grace = 0.0
		else:
			rejoin_grace = maxf(0.0,rejoin_grace-delta)
			if rejoin_grace <= 0.0: game_edge(0,false)
			return
	stage_time+=delta
	if pressure > 0.01:
		if not breath.playing: breath.play()
		breath.volume_db = -18 + pressure * 8 + radius * 4
		breath.pitch_scale = 0.8 + radius * 0.35
	else: breath.stop()
	match blow_phase:
		Blow.INFLATE:
			pressure=move_toward(pressure,1.0,delta*2.5)
			radius+=pressure*(0.092+radius*radius*(0.075+trial*0.008))*delta
			if radius>1.05:
				blow_phase=Blow.RESIDUAL
				stage_time=0
		Blow.RESIDUAL:
			pressure=move_toward(pressure,0.0,delta*2.2)
			var growth: float=pressure*(0.092+radius*radius*0.10)*delta
			radius+=growth
			residual+=growth
			if stage_time>=0.7:
				var target: Vector2=TARGETS[mini(trial,2)]
				var good: bool=radius>=target.x and radius<=target.y
				if good: successes+=1
				var outcome: String="合适" if good else ("偏小" if radius<target.x else "过大")
				outcomes.append(outcome)
				outcome_radii.append(radius)
				status_text=outcome
				blow_phase=Blow.RESULT
				stage_time=0
				play_feedback(good)
				set_progress(successes/3.0)
		Blow.READY:
			status_text="第%d口 · 提前收气" % (trial+1)
		_:
			pass

func on_time_expired() -> void:
	if successes>=2: complete_success({"successes":successes,"outcomes":outcomes},"糖泡成形了")
	else: complete_failure(&"shape_unsteady","下一口早点收气",{"successes":successes,"outcomes":outcomes})

func pause_media(value: bool) -> void:
	if is_instance_valid(breath): breath.stream_paused = value
	if not value and blow_phase == Blow.INFLATE: rejoin_grace = 0.35

func stop_media() -> void:
	if is_instance_valid(breath): breath.stop()

func get_presentation_state() -> Dictionary:
	var motion: StringName = &"ready"
	if blow_phase == Blow.INFLATE: motion = &"hold"
	elif blow_phase == Blow.RESIDUAL: motion = &"release"
	elif blow_phase == Blow.RESULT: motion = &"recover" if not outcomes.is_empty() and outcomes[-1] == "合适" else &"miss"
	return {"blow_phase": blow_phase, "radius": radius, "pressure": pressure, "action": motion,
		"outcome_count": outcomes.size(), "last_good": not outcomes.is_empty() and outcomes[-1] == "合适",
		"outcomes": outcomes.duplicate(), "outcome_radii": outcome_radii.duplicate(),
		"outcome_targets": TARGETS.duplicate()}

func draw_pixel_overlay() -> void:
	var target: Vector2 = TARGETS[mini(trial, 2)]
	var artwork := context.metadata.get(&"presentation") as HeritageTaskPresentation if context != null else null
	var generated := artwork != null and bool(artwork.properties.get("generated_sugar",false))
	var center := Vector2(590,330) if generated else Vector2(650,390)
	draw_arc(center,target.x*155,0,TAU,64,Color("ffedb4"),2)
	draw_arc(center,target.y*155,0,TAU,64,Color("ffedb4"),2)
	var prompt := "还在长，等它停稳" if blow_phase == Blow.RESIDUAL else "提前松开 · 停在两圈间"
	draw_rect(Rect2(444,170,330,40) if generated else Rect2(453,145,400,49),Color(.17,.11,.07,.9))
	label_at(Vector2(456,198) if generated else Vector2(472,176),prompt,24,PAPER)
	for i: int in outcomes.size():
		label_at(Vector2(408+i*178,574) if generated else Vector2(514+i*145,574),outcomes[i],24,PAPER)

func draw_scene() -> void:
	draw_rect(Rect2(0,420,1000,180),Color("bd9569"))
	person(Vector2(230,420),TEAL,pressure*0.5)
	draw_line(Vector2(260,350),Vector2(470,330),INK,8)
	var target: Vector2=TARGETS[mini(trial,2)]
	draw_arc(Vector2(600,320),target.x*155,0,TAU,64,GOLD,2)
	draw_arc(Vector2(600,320),target.y*155,0,TAU,64,GOLD,2)
	draw_circle(Vector2(600,320),maxf(8,radius*155),Color(0.8,0.42,0.22,0.35))
	draw_arc(Vector2(600,320),maxf(8,radius*155),0,TAU,64,RED,maxf(1,6-radius*5))
	draw_arc(Vector2(590,310),maxf(4,radius*130),PI,PI*1.4,20,PAPER,4)
	label_at(Vector2(400,515),"余胀中…" if blow_phase==Blow.RESIDUAL else status_text,26)
	for i: int in outcomes.size(): label_at(Vector2(340+i*130,560),outcomes[i],22)
