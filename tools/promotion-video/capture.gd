extends Node

# Isolated promotional capture harness. Inputs use the actual viewport and
# production scenes; no live scores, positions, judgments or success injection.
var mode := "board"
var folder := "res://artifacts/promotion-2026/board"
var capture: AudioEffectCapture
var chunks: Array[PackedVector2Array] = []
var sampling := false
var elapsed := 0.0
var marks: Array[Dictionary] = []
var frame_ms: Array[float] = []
var last_usec := 0
var pointer: RefCounted
var hud: HUD
var subject: PlayerClass
var scene: Node
var active_host: HeritageTaskHost
var debug_second := -1
const FEATURE_MODES := ["collection", "foodvariety", "event", "eventcards", "market", "ai", "professions", "achievements"]
var feature_cards: Array = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--take="): mode = arg.trim_prefix("--take=")
	folder = "res://artifacts/promotion-2026/" + mode
	DirAccess.make_dir_recursive_absolute(folder)
	Settings.load_preferences(folder+"/settings.cfg",folder+"/legacy.cfg")
	if mode != "trial" and mode != "musictrial": Settings.set_value("music_volume",0)
	HeritageMinigamePreferences.configure_storage_path(folder+"/minigames.cfg")
	DiscoveryManager._storage_path = folder+"/discovery.cfg"
	Engine.max_fps = 60
	var root := get_tree().root
	root.mode = Window.MODE_WINDOWED
	root.borderless = true
	root.size = Vector2i(1920,1080)
	root.position = Vector2i(20,20)
	root.title = "ChuwuzhiPromoCapture"
	root.always_on_top = true
	pointer = preload("res://tests/helpers/real_pointer_driver.gd").new(root,get_tree())
	if mode in FEATURE_MODES:
		await _feature_setup()
	elif mode in ["board","board2","trial","food"]:
		GameManager.configure_session(150926)
		GameManager.player_data = [{"name":"生活博主","job":"生活博主","location":"武汉"},{"name":"旅行博主","job":"旅行博主","location":"天门"}]
		await _scene("res://main_map.tscn")
		hud = get_tree().get_first_node_in_group("HUD") as HUD
		subject = TurnManager.players[0]
		# Fixed source deck and one food are declared initial demo fixtures.
		var han: 非遗牌 = load("res://Cards/非遗牌/武汉/汉剧.tres")
		var deck: Array = ResourceManager.地区非遗牌库[MapSection.REGION.武汉]
		deck.erase(han); deck.append(han)
		ResourceManager.add_food_card(subject,load("res://Cards/食物牌/热干面.tres"))
		hud._set_focus_mode(true); hud.map_zoom_factor = 1.7; hud.update_camera_view(0.0)
	elif mode == "home":
		await _scene("res://main_menu.tscn")
	elif mode == "tutorial":
		GameManager.begin_tutorial_session()
		await _scene("res://main_map.tscn")
		GameManager.tutorial_controller.progress_path = folder+"/tutorial.cfg"
	else:
		await _practice(mode if mode != "musictrial" else "han_ju")
	await _wait(.5)
	root.mode = Window.MODE_WINDOWED
	root.borderless = true
	root.size = Vector2i(1920,1080)
	root.position = Vector2i(20,20)
	root.title = "ChuwuzhiPromoCapture"
	DisplayServer.window_set_title(root.title)
	DisplayServer.window_move_to_foreground()
	await _wait(.7)
	get_tree().paused = true
	_write_json("ready.json",{"title":root.title,"size":[1920,1080]})
	while not FileAccess.file_exists(folder+"/go"):
		await _wait(.1)
	capture = AudioEffectCapture.new(); capture.buffer_length = 2.0
	AudioServer.add_bus_effect(0,capture)
	sampling = true; last_usec = Time.get_ticks_usec()
	await _wait(.3)
	await _sync()
	get_tree().paused = false
	_mark("content_start")
	if mode in FEATURE_MODES: await _features()
	elif mode in ["board","board2","trial","food"]: await _board()
	elif mode == "home":
		await _wait(12)
	elif mode == "tutorial":
		var lesson: TutorialController = GameManager.tutorial_controller
		await _wait(3); await _click(lesson.overlay.primary); await _wait(6)
		await _click_at(lesson.hud.get_tutorial_map_rect(TutorialDefinition.DESTINATION).get_center())
		await _wait(2); await _click(lesson.hud.btn_end_turn); await _wait(1)
		await _click(lesson.hud.btn_action); await _wait(5)
	else:
		await _wait(3)
		await _click(active_host._start_button)
		if active_host.active_task is HeritagePerformanceTask: await _music(active_host)
		elif mode == "tianmen_tang_su": await _sugar(active_host)
		elif mode == "ezhou_diaohua_jianzhi": await _paper(active_host)
		await _wait(5)
	_mark("content_end")
	get_tree().paused = true
	await _sync()
	await _wait(.3)
	sampling = false
	var file := FileAccess.open(folder+"/audio.f32",FileAccess.WRITE)
	for chunk in chunks: file.store_buffer(chunk.to_byte_array())
	file.close()
	_write_json("capture.json",{"mode":mode,"marks":marks,"mix_rate":AudioServer.get_mix_rate(),"frame_ms":frame_ms,"audio_frames":_sample_count(),"discarded_audio_frames":capture.get_discarded_frames(),"fixture":"Wuhan fixed first Hanju card; starting hot dry noodles; normal inputs and production transactions"})
	AudioServer.remove_bus_effect(0,AudioServer.get_bus_effect_count(0)-1)
	_write_json("done.json",{"complete":true})
	await _wait(4)
	get_tree().quit()

func _scene(path: String) -> void:
	if is_instance_valid(scene): scene.queue_free(); await get_tree().process_frame
	scene = load(path).instantiate()
	if mode in FEATURE_MODES and path == "res://main_map.tscn":
		scene.set_script(preload("res://tools/promotion-video/feature_map.gd"))
		scene.capture_mode = mode
	if mode in ["board","board2","trial","food"] and path == "res://main_map.tscn":
		scene.set_script(preload("res://tools/promotion-video/demo_map.gd"))
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await _wait(1.5)

func _feature_setup() -> void:
	if mode == "professions":
		await _scene("res://main_menu.tscn")
		return
	GameManager.configure_session(150926)
	GameManager.player_data = [{"name":"商业博主" if mode=="market" else "生活博主","job":"商业博主" if mode=="market" else "生活博主","location":"孝感","is_bot":mode=="ai"},{"name":"旅行博主","job":"旅行博主","location":"随州","is_bot":false}]
	await _scene("res://main_map.tscn")
	hud = get_tree().get_first_node_in_group("HUD") as HUD
	subject = TurnManager.players[0]
	hud._set_focus_mode(true); hud.map_zoom_factor=1.6; hud.update_camera_view(0)
	if mode == "ai": return
	for region in ResourceManager.地区非遗牌库:
		for card in ResourceManager.地区非遗牌库[region]:
			if card.base_score < 5 and feature_cards.size()<8: feature_cards.append(card)
	if mode == "collection":
		var first=load("res://Cards/非遗牌/武汉/木雕船模.tres")
		var deck=ResourceManager.地区非遗牌库[MapSection.REGION.武汉]
		deck.erase(first);deck.append(first)
		for card in feature_cards.slice(0,4): ResourceManager.add_feiyi_card(subject,card)
	elif mode == "market":
		subject.current_money=1500 # Initial mid-game capture fixture, before recording.
		for card in feature_cards.slice(0,4): MarketManager.deposit_card(card)
		ResourceManager.add_feiyi_card(subject,feature_cards[4])
	elif mode == "event":
		var card=load("res://Cards/事件牌/意外之喜.tres")
		ResourceManager.事件牌库.erase(card);ResourceManager.事件牌库.append(card)
	elif mode == "achievements":
		subject.current_energy=10 # Initial late-game fixture; food earns the achievement normally.
		ResourceManager.add_food_card(subject,load("res://Cards/食物牌/热干面.tres"))
	elif mode == "eventcards":
		for name in ["妙手回春","畅行无阻","金蝉脱壳"]:
			ResourceManager.add_event_card(subject,load("res://Cards/事件牌/%s.tres"%name))
	elif mode == "foodvariety":
		for name in ["热干面","云梦鱼面","英山角面","孝感麻糖","黄石港饼","沔阳三蒸"]:
			var path="res://Cards/食物牌/%s.tres"%name
			if ResourceLoader.exists(path): ResourceManager.add_food_card(subject,load(path))
	ResourceManager.calculate_victory_score(subject)
	hud._update_player_stats(subject)

func _features() -> void:
	if mode=="professions":
		await _wait(2)
		await _click_text(scene,"开始游戏")
		await _wait(1)
		await _click_text(scene,"本地游戏")
		await _wait(1)
		await _click_text(scene,"下一步")
		await _wait(2)
		var page=scene._player_setup_page
		for card in page._profession_cards.values():
			await _click(card);await _wait(3)
		return
	if mode=="ai":
		await _wait(65)
		return
	if mode=="achievements":
		while TurnManager.now_phase != TurnManager.TurnPhase.MOVING: await get_tree().process_frame
		await _click(hud.btn_end_turn);await _wait(.5)
		await _click(hud.btn_food);await _wait(3)
		await _click(hud.backpack_panel.grid_container.get_child(0).action_button)
		await _wait(5);await _click(hud.backpack_panel.btn_close);await _wait(1)
		var thumbs=hud.find_children("*","成就牌缩略图",true,false)
		if not thumbs.is_empty(): await _click(thumbs[0]);await _wait(6)
		await _click(hud.achievement_detail_overlay.close_button)
		await _click(hud.score_label);await _wait(4)
		return
	while TurnManager.now_phase != TurnManager.TurnPhase.MOVING: await get_tree().process_frame
	await _wait(1)
	if mode=="eventcards":
		await _click(hud.btn_end_turn);await _wait(1)
		for name in ["妙手回春","畅行无阻","金蝉脱壳"]:
			var card=load("res://Cards/事件牌/%s.tres"%name)
			await _click(hud._find_card_thumbnail(hud,card));await _wait(4)
			await _click_text(hud.event_overlay,"关闭");await _wait(.4)
		return
	if mode=="foodvariety":
		await _click(hud.btn_end_turn);await _wait(.5)
		await _click(hud.btn_food);await _wait(5)
		var items=hud.backpack_panel.grid_container.get_children()
		for item in items.slice(0,3):
			await _click_at(item.get_global_rect().get_center());await _wait(2)
		await _wait(3);return
	var kind=MapSection.SectionType.非遗
	if mode=="market": kind=MapSection.SectionType.研究所
	if mode=="event": kind=MapSection.SectionType.事件
	var target:MapSection
	for option in TurnManager.map.query_moves(subject):
		if option.type==kind and (mode!="collection" or option.region==MapSection.REGION.武汉): target=option;break
	if target==null: push_error("No feature target "+mode);get_tree().quit(2);return
	if mode=="market":
		hud._set_focus_mode(false);hud.map_zoom_factor=1.0;hud.update_camera_view(0);await _wait(1)
	_mark("route")
	await _click_at(hud.get_tutorial_map_rect(target.location_index).get_center());await _wait(3)
	await _click(hud.btn_end_turn);await _wait(.7)
	if mode=="event":
		var end=Time.get_ticks_msec()+18000
		while Time.get_ticks_msec()<end:
			await _wait(2)
			if hud.event_overlay.visible and hud.event_overlay._options_box.get_child_count()>0:
				await _click(hud.event_overlay._options_box.get_child(0))
		return
	await _click(hud.btn_action);await _wait(4)
	_mark("feature_open")
	if mode=="market":
		var grid=hud.market_overlay.card_grid
		await _click(grid.get_child(1).get_child(0));await _wait(3)
		await _click(grid.get_child(1).get_child(2));await _wait(4)
		await _click(hud.market_overlay.sell_tab);await _wait(3)
		await _click(grid.get_child(0).get_child(2));await _wait(3)
		await _click(hud.market_overlay.close_button);await _wait(2)
	else:
		await _click(hud.detail_panel.get_node("BtnClose"));await _wait(1)
		for card in feature_cards.slice(0,3):
			var thumb=hud._find_card_thumbnail(hud,card)
			await _click(thumb);await _wait(3)
			await _click(hud.detail_panel.get_node("BtnClose"));await _wait(.4)
		await _click(hud.score_label);await _wait(5)
		await _click(hud.score_overlay.rules_button);await _wait(4)
		await _click(hud.score_overlay.close_button)
		await _click(hud.guide_button);await _wait(4)

func _click_text(node:Node, text:String) -> bool:
	if node is FrontendStatefulCard and node.is_visible_in_tree() and text in node.title:
		await _click(node);return true
	if node is BaseButton and node.is_visible_in_tree() and node.get("text")!=null and text in str(node.get("text")):
		await _click(node);return true
	for child in node.get_children():
		if await _click_text(child,text): return true
	return false

func _practice(id: String) -> void:
	active_host = load("res://InheritanceTasks/UI/heritage_task_host.tscn").instantiate()
	get_tree().root.add_child(active_host)
	HeritageMinigamePreferences.complete_tutorial(StringName(id),6 if id=="han_ju" else 5)
	var context := HeritageTaskRunContext.new(StringName(id))
	context.avatar_id = &"life_blogger"
	context.metadata.skip_tutorial = true
	active_host.configure(load("res://InheritanceTasks/Definitions/%s.tres"%id),context)
	active_host.begin()
	await _wait(1)

func _board() -> void:
	while TurnManager.now_phase != TurnManager.TurnPhase.MOVING: await get_tree().process_frame
	_mark("map_route")
	await _wait(4)
	var choices: Dictionary = TurnManager.map.query_moves(subject)
	var destination: MapSection
	for option: MapSection in choices:
		if option.type == MapSection.SectionType.非遗 and option.region == MapSection.REGION.武汉:
			destination = option; break
	if destination == null:
		push_error("No Wuhan heritage destination: "+str(choices)); get_tree().quit(2); return
	await _click_at(hud.get_tutorial_map_rect(destination.location_index).get_center())
	await _wait(3)
	_mark("arrived",{"energy":subject.current_energy,"position":str(subject.now_pos)})
	await _click(hud.btn_end_turn)
	await _wait(.8)
	await _click(hud.btn_action)
	await _wait(3)
	_mark("hanju_before",{"card":hud.detail_panel.current_card.card_name,"score":subject.current_score})
	if mode=="trial": await _wait(3); return
	await _click(hud.detail_panel.get_node("BtnClose"))
	await _click(hud.btn_food); await _wait(5.0)
	_mark("food")
	var item: Node = hud.backpack_panel.grid_container.get_child(0)
	await _click(item.action_button)
	await _wait(3)
	await _click(hud.backpack_panel.btn_close)
	if mode == "food": await _wait(2); return
	await _wait(.5)
	var thumb := hud._find_card_thumbnail(hud,load("res://Cards/非遗牌/武汉/汉剧.tres"))
	await _click(thumb); await _wait(1.5)
	HeritageMinigamePreferences.complete_tutorial(&"han_ju",6)
	await _click(hud.detail_panel.task_button)
	await _wait(3)
	active_host = hud.detail_panel._task_host
	_mark("hanju_prepare")
	await _click(active_host._start_button)
	await _music(active_host)
	_mark("hanju_result",{"score":subject.current_score})
	await _wait(4)
	await _click(active_host.return_button)
	await _wait(2)
	_mark("hanju_after",{"score":subject.current_score,"inherited":HeritageTaskManager.is_inherited(load("res://Cards/非遗牌/武汉/汉剧.tres"))})
	await _wait(3)
	await _click(hud.detail_panel.get_node("BtnClose"))
	await _click(hud.score_label); await _wait(4)
	await _click(hud.score_overlay.close_button)
	await _click(hud.btn_end_turn); await _wait(6)
	_mark("second_player")
	_key(KEY_ALT,true); await get_tree().process_frame; _key(KEY_ALT,false)
	await _wait(8)

func _music(host: HeritageTaskHost) -> void:
	var task := host.active_task as HeritagePerformanceTask
	while task.phase != HeritageStageTask.Phase.LIVE:
		if host._terminal_emitted: return
		await get_tree().process_frame
	_mark("music_live")
	for event: Dictionary in task.chart.events:
		if event.kind == "rest": continue
		var target := int(event.time_ms)
		while task._judgment_ms() < target and not host._terminal_emitted: await get_tree().process_frame
		if host._terminal_emitted: break
		var key := KEY_D if int(event.get("direction",1))>0 else KEY_A
		_key(key,true); await get_tree().process_frame; _key(key,false)
		if mode=="musictrial" and elapsed>13: return
	while not host._terminal_emitted: await get_tree().process_frame
	_mark("music_done",{"feedback":task.judge.feedback_records})

func _sugar(host: HeritageTaskHost) -> void:
	var task: HeritageStageTask = host.active_task
	while task.phase != HeritageStageTask.Phase.LIVE: await get_tree().process_frame
	_mark("sugar_live")
	var holding := false
	while not host._terminal_emitted:
		if int(task.get("blow_phase"))==0 and not holding:
			_key(KEY_SPACE,true); holding=true
		elif int(task.get("blow_phase"))==1 and holding and float(task.get("radius")) >= [.60,.70,.63][int(task.get("trial"))]:
			_key(KEY_SPACE,false); holding=false; _mark("sugar_release")
		await get_tree().process_frame
	_mark("sugar_done")

func _paper(host: HeritageTaskHost) -> void:
	var task: HeritageStageTask = host.active_task
	while task.phase != HeritageStageTask.Phase.LIVE: await get_tree().process_frame
	_mark("paper_live")
	var lines: Array = task.get("contours")
	for line: PackedVector2Array in lines:
		await _wait(.5)
		var p: Vector2 = line[0]
		_paper_input(task,p,0)
		await get_tree().process_frame
		_paper_input(task,p,1)
		for i in range(1,line.size()):
			var steps := maxi(1,ceili(p.distance_to(line[i])/3.8))
			var start := p
			for j in range(1,steps+1):
				p = start.lerp(line[i],float(j)/steps)
				_paper_input(task,p,0)
				await get_tree().process_frame
		_paper_input(task,p,-1)
		_mark("paper_cut",{"segment":task.get("segment")})
	while not host._terminal_emitted: await get_tree().process_frame
	_mark("paper_done")

func _paper_input(task: Control, p: Vector2, button: int) -> void:
	var factor := minf(task.size.x/1000.0,task.size.y/600.0)
	var position := task.get_global_transform_with_canvas() * ((task.size-Vector2(1000,600)*factor)*.5+p*factor)
	if button == 0:
		var e := InputEventMouseMotion.new(); e.position=position; e.global_position=position; e.button_mask=MOUSE_BUTTON_MASK_LEFT
		get_tree().root.push_input(e,true)
	else:
		var e := InputEventMouseButton.new(); e.position=position; e.global_position=position; e.button_index=MOUSE_BUTTON_LEFT; e.pressed=button>0
		get_tree().root.push_input(e,true)

func _process(delta: float) -> void:
	if not sampling: return
	elapsed += delta
	var now := Time.get_ticks_usec()
	frame_ms.append((now-last_usec)/1000.0); last_usec = now
	if capture != null and capture.get_frames_available()>0:
		chunks.append(capture.get_buffer(capture.get_frames_available()))
	if int(elapsed)/10 != debug_second:
		debug_second = int(elapsed)/10
		if is_instance_valid(active_host) and active_host.active_task is HeritagePerformanceTask:
			var t: HeritagePerformanceTask = active_host.active_task
			print("CLOCK ", elapsed, " phase ",t.phase," state ",t.run_state," pos ",t.clock.get_playback_position()," paused ",t.clock.stream_paused," playing ",t.clock.playing," process ",t.can_process())

func _sync() -> void:
	var layer := CanvasLayer.new(); layer.layer=120; add_child(layer)
	var white := ColorRect.new(); white.color=Color.WHITE; white.size=Vector2(2560,1600); layer.add_child(white)
	var tone := AudioStreamWAV.new(); tone.mix_rate=48000; tone.format=AudioStreamWAV.FORMAT_16_BITS
	var bytes := PackedByteArray(); bytes.resize(9600)
	for i in 4800: bytes.encode_s16(i*2,int(sin(TAU*1000.0*i/48000.0)*12000.0))
	tone.data=bytes
	var voice := AudioStreamPlayer.new(); voice.stream=tone; add_child(voice); voice.play()
	_mark("sync")
	await _wait(.2); layer.queue_free(); voice.queue_free(); await _wait(.4)

func _key(code: Key, down: bool) -> void:
	var event := InputEventKey.new(); event.keycode=code; event.physical_keycode=code; event.pressed=down
	get_tree().root.push_input(event,true)

func _click(control: Control) -> void:
	if not is_instance_valid(control): push_error("Missing capture control"); return
	await pointer.click(control)
	await _wait(.25)

func _click_at(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new(); motion.position=position; motion.global_position=position
	get_tree().root.push_input(motion,true); await get_tree().process_frame
	var e := InputEventMouseButton.new(); e.position=position; e.global_position=position; e.button_index=MOUSE_BUTTON_LEFT; e.pressed=true
	get_tree().root.push_input(e,true); await get_tree().process_frame
	e=e.duplicate(); e.pressed=false; get_tree().root.push_input(e,true)

func _wait(seconds: float) -> void: await get_tree().create_timer(seconds,true).timeout
func _mark(label: String, data: Dictionary={}) -> void:
	marks.append({"label":label,"seconds":elapsed,"audio_sample":_sample_count(),"data":data})
	print("PROMO ",label," ",elapsed)
func _sample_count() -> int:
	var total := 0
	for chunk in chunks: total+=chunk.size()
	return total
func _write_json(name: String, data: Dictionary) -> void:
	var f := FileAccess.open(folder+"/"+name,FileAccess.WRITE); f.store_string(JSON.stringify(data,"\t")); f.close()
