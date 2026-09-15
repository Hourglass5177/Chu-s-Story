extends GutTest

const Driver = preload("res://tools/heritage_motion_input_driver.gd")
const AVATARS := [&"travel_blogger",&"life_blogger",&"business_blogger",&"food_blogger",&"adventure_blogger",&"magic_blogger"]

## Deterministic audio-time seam for comparison only. Native original-audio
## complete runs are recorded separately by play_heritage_motion_pixel.gd.
class FixtureMusicClock extends HeritageMusicClock:
	var timeline := 0.0
	func seconds() -> float:
		if timeline>=42.3:stop()
		return timeline

func test_shennong_six_appearances_and_no_art_have_identical_results() -> void:
	_compare_appearances("yandi_shennong_chuanshuo")

func test_cart_six_appearances_and_no_art_have_identical_results() -> void:
	_compare_appearances("dong_yong_chuanshuo")

func test_xingshan_six_appearances_and_no_art_have_identical_results() -> void:
	_compare_appearances("xingshan_min_ge")

func test_shenzhou_six_appearances_and_no_art_have_identical_results() -> void:
	_compare_appearances("xisai_shenzhou_hui")

func _compare_appearances(id: String) -> void:
	var baseline: Dictionary = {}
	for art: bool in [false,true]:
		for avatar: StringName in AVATARS:
			var result := _run(id,avatar,art)
			assert_eq(result.get("status"),HeritageTaskResult.Status.SUCCESS,"%s %s art=%s"%[id,avatar,art])
			if baseline.is_empty():baseline=result
			else:assert_eq(result,baseline,"Appearance cannot change inputs/physics/score: "+str(avatar))

func _run(id: String, avatar: StringName, art: bool) -> Dictionary:
	var definition := load("res://InheritanceTasks/Definitions/%s.tres"%id) as HeritageTaskDefinition
	var task := definition.instantiate_task()
	add_child(task)
	task.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	task.size=Vector2(1280,720)
	var music: FixtureMusicClock
	if id=="xingshan_min_ge":
		music=FixtureMusicClock.new()
		task.add_child(music)
		task.set("clock",music)
	var context := HeritageTaskRunContext.new(definition.task_id)
	context.test_mode=true
	context.avatar_id=avatar
	context.metadata["skip_tutorial"]=true
	if art:context.metadata[&"presentation"]=definition.presentation
	task.configure(context)
	var results: Array[HeritageTaskResult]=[]
	task.task_completed.connect(func(result:HeritageTaskResult)->void:results.append(result))
	task.start_task()
	task.set_process(false)
	task.set_physics_process(false)
	if task is HeritageStageTask:
		for frame: int in 380:
			if task.phase==HeritageStageTask.Phase.LIVE:break
			task._process(1.0/120.0)
	var controls: Dictionary={}
	for frame: int in 5500:
		if task.run_state==HeritageTaskBase.RunState.FINISHED:break
		match id:
			"yandi_shennong_chuanshuo":Driver.platform(task,1.0/120.0,controls)
			"dong_yong_chuanshuo":Driver.cart(task)
			"xingshan_min_ge":
				var desired:=300.0
				for gate:Dictionary in task.get("gates"):
					if not gate.done:
						desired=float(gate.y)
						break
				var y:=float(task.get("bird_y"))
				var speed:=float(task.get("vertical_speed"))
				if y+speed*.1>desired+40 and speed>-50:
					Driver.edge(task,&"ui_accept",false)
					Driver.edge(task,&"ui_accept",true)
				elif y<desired-15:Driver.edge(task,&"ui_accept",false)
				music.timeline+=1.0/120.0
			"xisai_shenzhou_hui":preload("res://tests/support/action_story_input.gd").escort(task)
		task._process(1.0/120.0)
	var result:Dictionary={}
	if results.size()==1:result={"status":results[0].status,"metrics":results[0].metrics}
	assert_eq(is_instance_valid(task.pixel_stage),art,"Art fixture constructed as requested")
	task.free()
	return result
