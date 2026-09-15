extends "res://tools/preview_heritage_minigames.gd"

## User-operated preview. Samples only wall time, phase and device family;
## no keys, recordings or per-frame disk writes. Flush when returning to gallery.
var _host_id := 0
var _task_id := ""
var _last_tick := 0
var _device := ""
var _switch_tick := -1000000
var _buckets: Dictionary = {}
var _runs: Array[Dictionary] = []

func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	# Delay main-menu loading until autoloads exist (SceneTree --script startup).
	var menu: Node = current_scene
	var host := menu.get("_practice_host") as HeritageTaskHost if menu != null else null
	if not is_instance_valid(host):
		if _host_id!=0: _flush()
		_last_tick=now
		return false
	if host.get_instance_id()!=_host_id:
		if _host_id!=0: _flush()
		_host_id=host.get_instance_id(); _task_id=String(host.definition.task_id)
		_last_tick=now; _device=""; _switch_tick=-1000000
	var task := host.active_task
	if not is_instance_valid(task): return false
	var family := String(task.get_input_device())
	if not _device.is_empty() and family!=_device: _switch_tick=now
	_device=family
	var phase := "prepare" if not host.get("_challenge_started") else "result" if host.result_panel.visible else "paused" if task.run_state==HeritageTaskBase.RunState.SUSPENDED else "live" if task is HeritageStageTask and task.phase==HeritageStageTask.Phase.LIVE else "teaching_or_countdown"
	var key := phase+("_switch" if now-_switch_tick<150000 else "_steady")
	if not _buckets.has(key): _buckets[key]={"frames":0,"total_ms":0.0,"max_ms":0.0,"over_33ms":0,"over_50ms":0,"histogram":{}}
	var bucket: Dictionary=_buckets[key]
	var ms: float=(now-_last_tick)/1000.0
	bucket.frames+=1; bucket.total_ms+=ms; bucket.max_ms=maxf(bucket.max_ms,ms)
	if ms>33.3: bucket.over_33ms+=1
	if ms>50: bucket.over_50ms+=1
	var bin := int(ceilf(ms))
	bucket.histogram[bin]=int(bucket.histogram.get(bin,0))+1
	_last_tick=now
	return false

func _flush() -> void:
	for bucket: Dictionary in _buckets.values():
		var bins: Array=bucket.histogram.keys(); bins.sort()
		var accumulated := 0
		for bin: int in bins:
			accumulated+=int(bucket.histogram[bin])
			if not bucket.has("p95_ms_upper_bound") and accumulated>=bucket.frames*.95: bucket.p95_ms_upper_bound=bin
			if accumulated>=bucket.frames*.99:
				bucket.p99_ms_upper_bound=bin; break
		bucket.average_fps=1000.0*bucket.frames/maxf(.001,bucket.total_ms)
	_runs.append({"task":_task_id,"renderer":RenderingServer.get_current_rendering_method(),"buckets":_buckets.duplicate(true)})
	DirAccess.make_dir_recursive_absolute("res://artifacts/performance-gallery")
	FileAccess.open("res://artifacts/performance-gallery/user-play.json",FileAccess.WRITE).store_string(JSON.stringify(_runs,"\t"))
	print("USER_PERFORMANCE_SAVED: ",_task_id," -> artifacts/performance-gallery/user-play.json")
	_buckets.clear(); _host_id=0
