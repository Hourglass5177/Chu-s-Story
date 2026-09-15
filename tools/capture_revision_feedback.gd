extends "res://tools/capture_revision_host.gd"

## Actual host, audio clock and ordinary inputs. No score/position injection.
func _run() -> void:
	folder = "res://artifacts/input-revision/feedback"
	DirAccess.make_dir_recursive_absolute(folder)
	root.size = Vector2i(1280,720)
	for path: String in DirAccess.get_files_at("res://InheritanceTasks/Definitions"):
		if not path.ends_with(".tres"): continue
		await _make(path.get_basename())
		await create_timer(.12).timeout
		await _shot("prepare-"+path.get_basename())
	await _make("laohekou_si_xian")
	host.start_from_preparation(false)
	var task := host.active_task as HeritagePerformanceTask
	while task.phase != HeritageStageTask.Phase.LIVE: await process_frame
	for index: int in 3:
		var target: int = int(task.chart.events[index].time_ms) + (120 if index==1 else 0)
		if index==2: target += 210
		while task._judgment_ms() < target: await process_frame
		if index < 2:
			_key(KEY_SPACE,true)
			_key(KEY_SPACE,false)
		await create_timer(.06).timeout
		await _shot(["grade-excellent","grade-good","grade-miss"][index])
	print("ACTUAL_AUDIO_INPUT_GRADES ",JSON.stringify(task.judge.feedback_records))
	await _make("xisai_shenzhou_hui")
	host.start_from_preparation(false)
	var boat := host.active_task as HeritageStageTask
	while boat.phase != HeritageStageTask.Phase.LIVE: await process_frame
	_key(KEY_D,true); _key(KEY_D,false)
	_key(KEY_W,true)
	await create_timer(1.5).timeout
	await _shot("boat-approach")
	_key(KEY_W,false)
	host.cancel()
	quit()
