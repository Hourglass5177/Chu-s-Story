extends "res://tools/capture_revision_host.gd"

const Driver := preload("res://tests/support/action_story_input.gd")
var driving := false

func _process(_delta: float) -> bool:
	if driving and is_instance_valid(host) and is_instance_valid(host.active_task):
		if host.active_task.phase==HeritageStageTask.Phase.LIVE and host.active_task.run_state==HeritageTaskBase.RunState.RUNNING:
			Driver.escort(host.active_task)
	return false

func _run() -> void:
	folder = "res://artifacts/escort-route-v5"
	DirAccess.make_dir_recursive_absolute(folder)
	root.size=Vector2i(1280,720)
	var menu = load("res://main_menu.tscn").instantiate()
	root.add_child(menu)
	menu.open_game_guide()
	var guide = menu.get_game_guide()
	var reveal := InputEventKey.new()
	reveal.keycode=KEY_D; reveal.ctrl_pressed=true; reveal.shift_pressed=true; reveal.pressed=true
	guide._input(reveal)
	guide.open_minigame_gallery()
	await create_timer(.6).timeout
	await _shot("gallery-names")
	menu.queue_free(); await process_frame
	for id: String in ["xia_lian_dan_shu","tujia_saye_erhe","xisai_shenzhou_hui"]:
		await _make(id)
		await create_timer(.25).timeout
		await _shot("title-"+id)
	host.start_from_preparation(false)
	driving=true
	var captured: Dictionary = {}
	var started := Time.get_ticks_msec()
	while host.active_task.run_state!=HeritageTaskBase.RunState.FINISHED and Time.get_ticks_msec()-started<42000:
		var d: float = host.active_task.distance
		for marker: int in [1800,2300,2500,2800,4600,5100,5500]:
			if d>=marker and not captured.has(marker):
				captured[marker]=true
				await _shot("route-"+str(marker))
		await process_frame
	driving=false
	await _shot("result")
	var result := {"distance":host.active_task.distance,"collisions":host.active_task.collisions,"seconds":host.active_task.game_time,"reaction_seconds":.45}
	FileAccess.open(folder+"/play.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("ESCORT_ROUTE_PLAY: ",result)
	host.cancel()
	quit()
