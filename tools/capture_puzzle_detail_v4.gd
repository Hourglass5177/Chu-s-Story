extends "res://tools/capture_revision_host.gd"

func _run() -> void:
	folder = "res://artifacts/puzzle-detail-v4"
	DirAccess.make_dir_recursive_absolute(folder)
	for resolution: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1600)]:
		root.size = resolution
		await _make("xiabaoping_minjian_gushi")
		host.start_from_preparation(false)
		await create_timer(3.6).timeout
		await _shot("live-"+str(resolution.x))
		# Use the generated legal solution through normal keyboard events.
		for step: Variant in host.active_task.candidates[0].solution:
			var code: Key = {-1:KEY_A,1:KEY_D,-2:KEY_W,2:KEY_S}[int(step)]
			_key(code,true); _key(code,false)
			await create_timer(.15).timeout
		await _shot("reveal-"+str(resolution.x))
		await create_timer(3.3).timeout
		await _shot("second-"+str(resolution.x))
		# Resize the ongoing board; never reset its timer/seed.
		root.size = Vector2i(1280,720)
		await create_timer(.2).timeout
		await _shot("resized-from-"+str(resolution.x))
	await _make("xiabaoping_minjian_gushi",true)
	host.start_from_preparation(true)
	await create_timer(.5).timeout
	await _shot("teaching")
	host.cancel()
	quit()
