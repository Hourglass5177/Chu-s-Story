class_name BoardDicePresenter
extends Control

## Presentation receives committed faces. It never reads or advances the rules RNG.
var _serial := 0
var _faces: Array[TextureRect] = []
var _caption: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 110
	MainUI.fill(self)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	MainUI.fill(center)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", MainUI.box("panel", 48))
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)
	_caption = Label.new()
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MainUI.pixel_label(_caption, 48)
	column.add_child(_caption)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(row)
	for index in range(2):
		var face := TextureRect.new()
		face.custom_minimum_size = Vector2(320, 320)
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(face)
		_faces.append(face)
	hide()

func play(player: PlayerClass, values: Array[int], still_current: Callable) -> void:
	if GameManager.is_headless_simulation() or values.is_empty(): return
	_serial += 1
	var serial := _serial
	for index in range(_faces.size()): _faces[index].visible = index < values.size()
	show()
	var elapsed := 0.0
	var landed := false
	BoardSfx.request(&"dice_roll", player)
	while elapsed < 1.5 and serial == _serial and still_current.call():
		await get_tree().process_frame
		if not is_instance_valid(player): break
		if get_tree().paused: continue
		var ai := get_tree().get_first_node_in_group("AI_SESSION")
		var speed: float = ai.get_speed_multiplier() if player.is_bot and ai != null else 1.0
		elapsed += get_process_delta_time() * speed
		if elapsed >= 0.7 and not landed:
			landed = true
			BoardSfx.stop_cue(&"dice_roll")
			BoardSfx.request(&"dice_land", player)
		_caption.text = "%s · 掷骰中" % player.player_name if elapsed < 0.7 else "%s · %s 点" % [player.player_name, " + ".join(values.map(func(value): return str(value)))]
		for index in range(mini(values.size(), _faces.size())):
			var face := _faces[index]
			var rolling := elapsed < 0.7
			var value := 1 + posmod(int(elapsed * 26) + index * 3, 6) if rolling else values[index]
			face.texture = MainUI.texture("dice_%d" % clampi(value, 1, 6))
			face.pivot_offset = face.size * 0.5
			face.rotation = sin(elapsed * 38 + index) * 0.26 * maxf(0, 1 - elapsed / 0.9)
			face.scale = Vector2.ONE * (1.0 + sin(elapsed * 30) * 0.06 * maxf(0, 1 - elapsed / 0.9))
	if serial == _serial:
		BoardSfx.stop_cue(&"dice_roll")
		hide()

func cancel() -> void:
	_serial += 1
	BoardSfx.stop_cue(&"dice_roll")
	hide()
