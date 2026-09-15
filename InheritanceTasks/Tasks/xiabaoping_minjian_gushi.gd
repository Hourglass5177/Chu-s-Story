extends HeritageStageTask

signal story_replay_finished
const Catalog := preload("res://InheritanceTasks/Data/story_puzzle_catalog.gd")
const GOAL: Array[int] = [1,2,3,4,5,6,7,8,0]
const BOARD_RECT := Rect2(45,115,420,420)
const REFERENCE_RECT := Rect2(572,170,252,252)
const CELL: float = 140.0
const SLIDE_SECONDS: float = 0.12
const REVEAL_SECONDS: float = 3.2
var board: Array[int] = []
var empty_index: int = 8
var story_index: int = -1
var scene_index: int = 0
var puzzle_depth: int = 0
var moves: int = 0
var completed_scenes: int = 0
var operation_seconds: float = 0.0
var reveal_left: float = 0.0
var slide_left: float = 0.0
var slide_from: int = -1
var slide_to: int = -1
var slide_tile: int = 0
var scene_texture: Texture2D
var reference_texture: Texture2D
var candidates: Array[Dictionary] = []
var invalid_feedback: float = 0.0
var lesson_moves: int = 0
var replaying: bool = false
var replay_paused: bool = false
var replay_seconds: float = 0.0
var replay_saved_scene: int = 0
var replay_saved_board: Array[int] = []
var replay_saved_empty: int = 8

func input_profile_kind() -> StringName: return &"puzzle"
func play_feedback(good: bool) -> void:
	if is_instance_valid(sfx): sfx.stream = load("res://InheritanceTasks/Audio/action-story-v3/puzzle-%s.wav"%("good" if good else "miss"))
	super.play_feedback(good)
	if is_instance_valid(sfx):
		sfx.pitch_scale = 1.0
		sfx.volume_db = -16.0

func tutorial_version() -> int: return 4
func tutorial_overlay_bounds() -> Rect2: return Rect2(520,445,445,105)
func feedback_overlay_bounds() -> Rect2: return Rect2(40,28,920,62)

func _setup_pixel_stage() -> void:
	super._setup_pixel_stage()
	# The board renders the original texture directly, not a low-res viewport.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func setup_game() -> void:
	duration_seconds = 120.0
	operation_seconds = 0.0
	time_left = duration_seconds
	completed_scenes = 0
	moves = 0
	reveal_left = 0.0
	slide_left = 0.0
	invalid_feedback = 0.0
	lesson_moves = 0
	lesson_text = "把相邻的一块推入空格"
	# Tutorial resets keep the selected story and the three challenge boards.
	if story_index < 0:
		var rng := RandomNumberGenerator.new()
		rng.seed = context.random_seed
		story_index = rng.randi_range(0, Catalog.STORIES.size() - 1)
		for scene: int in 3:
			var entry := Catalog.candidate(rng, scene)
			if entry.is_empty():
				complete_technical_error(&"missing_puzzle_bank", "拼图数据未就绪")
				return
			candidates.append(entry)
	_load_scene(0)

func _load_scene(index: int) -> void:
	scene_index = index
	board.assign(candidates[index].board)
	puzzle_depth = int(candidates[index].depth)
	empty_index = board.find(0)
	slide_left = 0.0
	reveal_left = 0.0
	var path := Catalog.image_path(story_index, scene_index)
	scene_texture = load(path) as Texture2D if ResourceLoader.exists(path) else null
	reference_texture = scene_texture
	if scene_texture == null:
		complete_technical_error(&"missing_story_image","故事图片未就绪")
		return
	if reference_texture == null: reference_texture = scene_texture
	status_text = "%s · 第%d幕" % [Catalog.STORIES[story_index].title, scene_index + 1]

func begin_practice() -> void:
	board = [1,2,3,4,0,5,7,8,6]
	empty_index = 4
	lesson_text = "点空格旁的拼块；方向键移动空格"

func begin_game() -> void:
	_load_scene(0)
	operation_seconds = 0.0
	game_time = 0.0
	time_left = duration_seconds
	set_progress(0.0)

func task_tick(delta: float) -> void:
	if phase != Phase.LIVE or resume_countdown > 0.0:
		super.task_tick(delta)
		return
	feedback_age = maxf(0.0, feedback_age - delta)
	invalid_feedback = maxf(0.0, invalid_feedback - delta)
	if reveal_left > 0.0:
		reveal_left = maxf(0.0, reveal_left - delta)
		if reveal_left <= 0.0:
			if completed_scenes == 3:
				complete_success({"story":Catalog.STORIES[story_index].id,"moves":moves,"operation_seconds":operation_seconds,"depths":candidates.map(func(e: Dictionary) -> int: return int(e.depth))}, "三幕故事拼好了")
			else: _load_scene(scene_index + 1)
		return
	slide_left = maxf(0.0, slide_left - delta)
	operation_seconds = minf(duration_seconds, operation_seconds + delta)
	game_time = operation_seconds
	time_left = maxf(0.0, duration_seconds - operation_seconds)
	if time_left <= 0.0: on_time_expired()

func demo_tick(_delta: float) -> void:
	board.assign([1,2,3,4,5,6,7,0,8] if phase_time < 1.2 else GOAL)
	empty_index = board.find(0)

func practice_tick(delta: float) -> void:
	slide_left = maxf(0.0, slide_left - delta)
	invalid_feedback = maxf(0.0,invalid_feedback-delta)
	if lesson_moves >= 2 and slide_left <= 0.0: finish_lesson()

func practice_edge(direction: int, down: bool) -> void:
	if down: _direction_move(direction)

func game_edge(direction: int, down: bool) -> void:
	if down: _direction_move(direction)

func _direction_move(direction: int) -> void:
	var offset: int = {-1:-1,1:1,-2:-3,2:3}.get(direction,0)
	if offset != 0: move_tile(empty_index + offset)

func move_tile(index: int) -> bool:
	if phase not in [Phase.LIVE,Phase.PRACTICE] or not is_input_active() or resume_countdown > 0.0 or reveal_left > 0.0 or slide_left > 0.0: return false
	if index < 0 or index >= 9 or absi(index / 3 - empty_index / 3) + absi(index % 3 - empty_index % 3) != 1:
		if invalid_feedback <= 0.0: play_feedback(false)
		invalid_feedback = .8
		return false
	slide_from = index
	slide_to = empty_index
	slide_tile = board[index]
	board[empty_index] = board[index]
	board[index] = 0
	empty_index = index
	slide_left = SLIDE_SECONDS
	moves += 1
	play_feedback(true)
	if phase == Phase.PRACTICE: lesson_moves += 1
	elif board == GOAL:
		completed_scenes += 1
		reveal_left = REVEAL_SECONDS
		set_progress(completed_scenes / 3.0)
		status_text = Catalog.STORIES[story_index].scenes[scene_index].title
	return true

func task_gui_input(event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		if input_profile != null: input_profile.note_pointer_motion(event.relative)
		return false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if input_profile != null: input_profile.pointer_edge(0,event.pressed)
		if event.pressed:
			var p := logical_point(event.position)
			if BOARD_RECT.has_point(p): move_tile(int((p.y-BOARD_RECT.position.y)/CELL)*3+int((p.x-BOARD_RECT.position.x)/CELL))
		return true
	return false

func on_time_expired() -> void:
	complete_failure(&"puzzle_unfinished", "时间到了，再看原图试一试", {"story":Catalog.STORIES[story_index].id,"scenes":completed_scenes,"moves":moves})

func get_time_display() -> String:
	if phase != Phase.LIVE or resume_countdown > 0: return super.get_time_display()
	# The TV dial is a small status badge; the full clock belongs in the board HUD.
	return "故事" if reveal_left > 0.0 else "拼图"

func puzzle_hud_state() -> Dictionary:
	var seconds := maxi(0,ceili(time_left))
	var clock := "剩余 %d:%02d" % [seconds/60,seconds%60]
	if replaying: clock = "故事回看"
	elif phase != Phase.LIVE: clock = "练习不计时" if is_tutorial_active() else "准备开始"
	elif reveal_left > 0.0: clock = "计时暂停"
	elif run_state == RunState.FINISHED: clock = "三幕完成" if completed_scenes == 3 else "时间到"
	return {"story":str(Catalog.STORIES[story_index].title),"scene":"第 %d / 3 幕"%(scene_index+1),"clock":clock}

func replay_story() -> void:
	if run_state != RunState.FINISHED or replaying: return
	replaying = true
	replay_paused = false
	replay_seconds = 0.0
	replay_saved_scene = scene_index
	replay_saved_board = board.duplicate()
	replay_saved_empty = empty_index
	_load_scene(0)
	board = GOAL.duplicate()
	queue_redraw()

func set_suspended(suspended: bool) -> void:
	if replaying:
		replay_paused = suspended
		return
	super.set_suspended(suspended)

func _process(delta: float) -> void:
	if not replaying:
		super._process(delta)
		return
	if replay_paused: return
	replay_seconds += delta
	var next := mini(2,int(replay_seconds/4.5))
	if next != scene_index:
		_load_scene(next)
		board = GOAL.duplicate()
	if replay_seconds >= 13.5: _end_replay()
	queue_redraw()

func _end_replay() -> void:
	if not replaying: return
	replaying = false
	_load_scene(replay_saved_scene)
	board = replay_saved_board.duplicate()
	empty_index = replay_saved_empty
	story_replay_finished.emit()

func draw_scene() -> void:
	if board.size()!=9: return
	draw_rect(Rect2(Vector2.ZERO,STAGE),Color("e9d9b4"))
	_draw_puzzle_hud()
	draw_rect(BOARD_RECT.grow(10),Color("644b36"))
	draw_rect(BOARD_RECT,Color("392d29"))
	var show_complete := replaying or reveal_left > 0.0 or (run_state == RunState.FINISHED and completed_scenes == 3)
	for cell: int in 9:
		var tile: int = board[cell]
		if tile == 0 and not show_complete: continue
		if tile == 0: tile = 9
		if slide_left > 0.0 and cell == slide_to and not show_complete: continue
		var tile_rect := Rect2(BOARD_RECT.position+Vector2(cell%3,cell/3)*CELL,Vector2.ONE*CELL)
		_draw_piece(tile,tile_rect)
		if not show_complete and slide_left <= 0.0 and absi(cell/3-empty_index/3)+absi(cell%3-empty_index%3)==1:
			draw_rect(tile_rect.grow(-4),Color("ffe2a0") if invalid_feedback>0.0 else Color(.96,.86,.65,.58),false,3)
	if slide_left > 0.0 and not show_complete:
		var from := Vector2(slide_from%3,slide_from/3)*CELL
		var to := Vector2(slide_to%3,slide_to/3)*CELL
		_draw_piece(slide_tile,Rect2(BOARD_RECT.position+from.lerp(to,1.0-slide_left/SLIDE_SECONDS),Vector2.ONE*CELL))
	label_at(Vector2(572,142),"完整参考图",26)
	if reference_texture != null: draw_texture_rect(reference_texture,REFERENCE_RECT,false)
	else:
		draw_rect(REFERENCE_RECT,Color("dbc595"))
		label_at(REFERENCE_RECT.position+Vector2(20,110),Catalog.STORIES[story_index].scenes[scene_index].title,24)
		label_at(REFERENCE_RECT.position+Vector2(20,149),"新分镜制作中",22)
	if not is_tutorial_active():
		label_at(Vector2(45,574),"下堡坪地方传说 · 新编三幕",23)
	if show_complete:
		var text: String = Catalog.STORIES[story_index].scenes[scene_index].text
		for line: int in ceili(text.length()/16.0): label_at(Vector2(515,460+line*32),text.substr(line*16,16),24)
	else:
		label_at(Vector2(572,463),"选亮边这几块" if invalid_feedback>0.0 else "相邻拼块 → 空格",25)
		label_at(Vector2(572,501),"方向键移动的是空格",23)

func _draw_puzzle_hud() -> void:
	# Below the broadcast logo / teaching strip, above both image frames.
	var hud := puzzle_hud_state()
	draw_rect(Rect2(35,64,920,40),Color("644b36"))
	label_at(Vector2(49,94),hud.story,28,Color("fff0cc"))
	label_at(Vector2(345,94),hud.scene,26,Color("fff0cc"))
	label_at(Vector2(685,94),hud.clock,28,Color("fff0cc"))

func label_at(point: Vector2, text: String, font_size: int = 22, color: Color = INK) -> void:
	# This task draws directly, so it must opt into the same sharp cached font
	# as viewport-backed minigames instead of inheriting an antialiased UI font.
	if _stage_pixel_font == null: _stage_pixel_font = HeritageTelevisionStyle.pixel_font()
	draw_string(_stage_pixel_font,point,text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func _square_source() -> Rect2:
	var dimensions := scene_texture.get_size()
	var side := minf(dimensions.x,dimensions.y)
	return Rect2((dimensions-Vector2.ONE*side)*.5,Vector2.ONE*side)

func _draw_piece(tile: int, target: Rect2) -> void:
	if scene_texture != null:
		var square := _square_source()
		var n := tile-1
		draw_texture_rect_region(scene_texture,target,Rect2(square.position+Vector2(n%3,n/3)*square.size/3.0,square.size/3.0))
		draw_rect(target,Color("5e4b3a"),false,2)
	else:
		draw_rect(target,Color("caa474").lightened(float(tile%3)*.07))
		label_at(target.get_center()+Vector2(-10,9),str(tile),32)
