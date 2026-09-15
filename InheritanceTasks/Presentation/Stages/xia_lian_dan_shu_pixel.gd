extends HeritagePixelCanvas

const V2 := "res://InheritanceTasks/Art/Pixel/v2/runtime/alchemy/"
const V3 := "res://InheritanceTasks/Art/Pixel/v3/runtime/xia_lian_dan_shu/"
const PIXEL_FONT := preload("res://InheritanceTasks/Art/Pixel/v2/fonts/fusion-pixel-12px-proportional-zh_hans.ttf")
var _last_pump_frame: int = 0
var _was_pumping: bool = false
var _return_pull: float = 0.0
var _return_time: float = 0.0
var _pump_clock: float = -1.0
var _generated_phase: float = 0.0
var _generated_last_time: float = -1.0
var _generated_heat: float = 0.35
const PUMP_TIMES: Array[float] = [.15, .13, .17, .12, .09, .10, .14, .16]

func receive_visual_state(state: Dictionary) -> void:
	super.receive_visual_state(state)
	if artwork == null or artwork.version < 3: return
	var now := float(state.get("animation_time", 0.0))
	var delta := clampf(now - _generated_last_time, 0.0, .25) if _generated_last_time >= 0.0 else 0.0
	if now < _generated_last_time: _generated_phase = 0.0
	_generated_last_time = now
	if bool(state.get("held", false)) or _generated_phase > 0.0:
		_generated_phase += delta
		if _generated_phase >= 1.06:
			_generated_phase = fmod(_generated_phase, 1.06) if bool(state.get("held", false)) else 0.0
	_generated_heat = move_toward(_generated_heat, float(state.get("heat", .35)), delta * 1.1)

func paint() -> void:
	if artwork.version >= 3:
		paint_generated_workshop()
		return
	if artwork.version >= 2:
		paint_workshop()
		return
	paint_background()
	var heat := float(visual_state.get("heat", 0.35))
	var time := decoration_time()
	var flame_color := Color("ffc76b") if heat < 0.8 else Color("ffe2a1")
	for i: int in 8:
		var height := 12.0 + heat * 42.0 + sin(time * 9.0 + i * 1.9) * 7.0
		var point := Vector2(638 + i * 11, 366)
		draw_rect(Rect2(point - Vector2(0, height), Vector2(12, height)), Color("df6532"))
		draw_rect(Rect2(point - Vector2(-2, height * .7), Vector2(6, height * .7)), flame_color)
	paint_avatar(Rect2(104, -40, 448, 448), action())
	if heat > .18:
		for i: int in 4:
			var rise := fmod(time * (15 + heat * 20) + i * 25, 100.0)
			var shade := Color(.42, .36, .31, (.12 + heat * .17) * (1 - rise / 120))
			draw_rect(Rect2(Vector2(668 + sin(i * 2 + time) * 6, 153 - rise), Vector2(16 + i * 4, 10 + i * 2)), shade)
	paint_foreground()

func paint_workshop() -> void:
	paint_background()
	var heat := clampf(float(visual_state.get("heat", .35)), 0.0, 1.0)
	var target := float(visual_state.get("target", .42))
	var brew := float(visual_state.get("brew", .1))
	var held := bool(visual_state.get("held", false))
	var elapsed := clampf(animation_time() - _pump_clock, 0.0, .25) if _pump_clock >= 0.0 else 0.0
	_pump_clock = animation_time()
	var inside := absf(heat - target) <= .075
	var pulls := [0, 2, 5, 8, 10, 8, 5, 2]
	var pump_frame := int(local_action_time() * 10.0) % 8 if held else 0
	if held:
		_last_pump_frame = pump_frame
	elif _was_pumping:
		_return_pull = float(pulls[_last_pump_frame])
		_return_time = 0.0
	if not held and _return_pull > 0.0:
		_return_time += elapsed
		var pull := maxf(0.0, _return_pull * (1.0 - _return_time / .18))
		var distance := INF
		for i in 5:
			if absf(pulls[i] - pull) < distance:
				distance = absf(pulls[i] - pull)
				pump_frame = i
		if _return_time >= .18: _return_pull = 0.0
	_was_pumping = held
	var pose := action()
	# All contact positions use authored native coordinates: the grip is at
	# (176 + pull, 193), shared by both hands and the bellows handle.
	paint_native(V2 + "bellows.png", Vector2(171, 168), Rect2(pump_frame * 92, 0, 92, 70))
	var appearance := artwork.get_appearance(avatar_id)
	var avatar := avatar_texture(pose)
	if appearance != null and (pose in [&"action", &"release", &"hold"] or pump_frame > 0):
		avatar = appearance.sprite_frames.get_frame_texture(&"action", pump_frame)
	if avatar != null: draw_texture_rect(avatar, Rect2(184, 222, 192, 256), false)
	# Fire is behind the transparent firebox and never scales the furnace.
	var fire_frame := int(decoration_time() * 8.0) % 6
	var fire := asset(V2 + "fire.png")
	if fire != null:
		var fire_height := roundf(18.0 + heat * 27.0)
		var source := Rect2(fire_frame * 56, 48 - fire_height, 56, fire_height)
		draw_texture_rect_region(fire, Rect2(311 * 2, (209 - fire_height) * 2, 112, fire_height * 2), source)
	paint_native(V2 + "furnace.png", Vector2(263, 54))
	# Each puff is a deliberately small cluster. Reduced motion keeps the
	# heat-state signal, while suppressing ambient drift.
	var smoke := Color("747b7b") if heat < target - .075 else Color("c2c7ae")
	for i in 3:
		var rise := roundf(fmod(decoration_time() * (8.0 + heat * 9.0) + i * 13.0, 41.0))
		var p := Vector2(338 + (i % 2) * 3, 67 - rise)
		draw_rect(Rect2(p * 2, Vector2(8 + i * 3, 3) * 2), smoke)
		draw_rect(Rect2((p + Vector2(2, -2)) * 2, Vector2(4 + i * 3, 2) * 2), smoke)
	paint_native(V2 + "heat_gauge.png", Vector2(432, 37))
	# Logical coordinate conversion happens exactly once; every edge lands
	# on an even logical pixel, hence an integer native pixel.
	var low_y := roundf(54 + (1.0 - target - .075) * 187.0)
	draw_rect(Rect2(446 * 2, low_y * 2, 28, 56), Color("d5a36b"))
	draw_rect(Rect2(449 * 2, (low_y + 1) * 2, 16, 52), Color("f3ca67"))
	var heat_y := roundf(54 + (1.0 - heat) * 187.0)
	draw_colored_polygon(PackedVector2Array([Vector2(440, heat_y - 3) * 2, Vector2(447, heat_y) * 2, Vector2(440, heat_y + 3) * 2]), Color("faedcb"))
	draw_rect(Rect2(447 * 2, heat_y * 2, 25, 4), Color("fff3d6"))
	var trend := float(visual_state.get("target_trend", 0.0))
	var arrow_y := low_y + 12
	var arrow_x := 473.0
	var tip := -4.0 if trend > .01 else 4.0
	if absf(trend) > .01:
		draw_line(Vector2(arrow_x, arrow_y - tip) * 2, Vector2(arrow_x, arrow_y + tip) * 2, Color("44313b"), 2)
		draw_line(Vector2(arrow_x - 3, arrow_y) * 2, Vector2(arrow_x, arrow_y + tip) * 2, Color("44313b"), 2)
		draw_line(Vector2(arrow_x + 3, arrow_y) * 2, Vector2(arrow_x, arrow_y + tip) * 2, Color("44313b"), 2)
	else:
		draw_line(Vector2(470, arrow_y) * 2, Vector2(476, arrow_y) * 2, Color("44313b"), 2)
	paint_native(V2 + "brew_gauge.png", Vector2(79, 271))
	var fill_width := floorf(326.0 * brew)
	draw_rect(Rect2(86 * 2, 278 * 2, fill_width * 2, 20), Color("71834e"))
	draw_rect(Rect2(86 * 2, 278 * 2, fill_width * 2, 4), Color("c4c48a"))
	draw_rect(Rect2(roundf(86 + 326 * .70) * 2, 275 * 2, 4, 32), Color("fff3d6"))
	text_native(Vector2(438, 31), "火候", Color("44313b"))
	text_native(Vector2(29, 286), "炼制", Color("44313b"))
	text_native(Vector2(434, 286), "七成成炉", Color("44313b"))
	var status := "火候正好" if inside else ("添一点火" if heat < target else "收一收火")
	# This is a compact status label on the hearth, never a tutorial paragraph.
	draw_rect(Rect2(287 * 2, 240 * 2, 108 * 2, 19 * 2), Color("f4dfad"))
	text_native(Vector2(297, 254), status, Color("52634a") if inside else Color("624039"))

func text_native(at: Vector2, text: String, color: Color) -> void:
	draw_string(PIXEL_FONT, at * 2.0, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, color)

func paint_generated_workshop() -> void:
	paint_background()
	var frame := 0
	var remainder := _generated_phase
	for i in PUMP_TIMES.size():
		frame = i
		if remainder < PUMP_TIMES[i]: break
		remainder -= PUMP_TIMES[i]
	if _generated_phase <= 0.0 and not bool(visual_state.get("held",false)):
		match action():
			&"miss": frame = 8
			&"success": frame = 11
			&"release", &"recover": frame = 9 if local_action_time()<.35 else 10
			_: frame = 10
	var flames := asset(V3 + "fire.png")
	if flames != null:
		var fire_frame := int(decoration_time() / .105) % 4
		var level := clampi(int(_generated_heat * 3.0), 0, 2)
		# Fire is an independent layer; its base and the vessel never move.
		draw_texture_rect_region(flames, Rect2(666, 268, 154, 154), Rect2(fire_frame * 154, level * 154, 154, 154))
		draw_texture_rect_region(flames, Rect2(714, 460, 70, 42), Rect2(((fire_frame + 2) % 4) * 154, level * 154 + 70, 154, 84))
	paint_asset(V3 + "vessel-occlusion.png", Rect2(0,0,1000,600))
	var rod_anchors: Dictionary = artwork.properties.get("rod_anchors",{})
	var anchors: Array = rod_anchors.get(avatar_id,[])
	if frame<anchors.size():
		var end: Vector2 = (Vector2(90,86)+(anchors[frame] as Vector2))*2.0
		var inlet := Vector2(486,404)
		var shaft := asset(V3+"shaft.png")
		if shaft!=null and inlet.x>end.x:
			draw_set_transform(end,(inlet-end).angle())
			draw_texture_rect(shaft,Rect2(-4,-6,end.distance_to(inlet)+10,12),false)
			draw_set_transform(Vector2.ZERO)
	paint_asset(V3 + "bellows-fixed.png", Rect2(0,0,1000,600))
	var appearance := artwork.get_appearance(avatar_id)
	if appearance != null:
		var actor := appearance.atlas
		# Clip the rod where it enters the fixed box. This keeps generated
		# hand contact while preventing the extension passing through the wood.
		var top := Rect2(frame * 400, 0, 400, 224)
		draw_texture_rect_region(actor, Rect2(180, 172, 400, 224), top)
		draw_texture_rect_region(actor, Rect2(180, 396, 282, 28), Rect2(frame * 400, 224, 282, 28))
		draw_texture_rect_region(actor, Rect2(180, 424, 400, 148), Rect2(frame * 400, 252, 400, 148))
	else:
		# An unconverted identity stays itself until its new sheet is ready.
		var previous: HeritageTaskPresentation = artwork.properties.get("fallback_presentation")
		if previous != null:
			var old := previous.get_appearance(avatar_id)
			if old != null: draw_texture_rect(old.portrait, Rect2(180, 252, 192, 256), false)
	paint_generated_gauges()

func paint_generated_gauges() -> void:
	var heat := clampf(float(visual_state.get("heat", .35)), 0, 1)
	var target := float(visual_state.get("target", .42))
	var brew := float(visual_state.get("brew", .1))
	# Stable contrast panels are functional UI, not texture noise. The stage
	# renders at exactly 2 logical pixels per native pixel.
	var ink := Color("382e35")
	var paper := Color("f8e9c7")
	var wood := Color("8a5b43")
	var brass := Color("d7aa69")
	draw_style_box(_gauge_panel(wood, ink), Rect2(874, 46, 96, 438))
	draw_style_box(_gauge_panel(paper, brass), Rect2(886, 58, 72, 412))
	draw_rect(Rect2(904, 104, 32, 336), ink)
	for i in 11:
		draw_line(Vector2(940, 440-i*33.6).round(), Vector2(950, 440-i*33.6).round(), wood, 2)
	var target_y := roundf(104 + (1.0-target-.075)*336)
	draw_rect(Rect2(902,target_y,36,50),Color("c6bd71"))
	draw_rect(Rect2(908,target_y+2,24,46),Color("efe4a1"))
	var heat_y := roundf(104 + (1.0-heat)*336)
	draw_rect(Rect2(904,heat_y,32,440-heat_y),Color("cb6548"))
	# Target brackets remain visible even when heat fills this interval.
	draw_rect(Rect2(898,target_y,44,50),Color("fff0ac"),false,4)
	draw_line(Vector2(896,heat_y),Vector2(942,heat_y),paper,4)
	draw_colored_polygon(PackedVector2Array([Vector2(892,heat_y-7),Vector2(903,heat_y),Vector2(892,heat_y+7)]),ink)
	text_native(Vector2(449,43), "火候", ink)
	var trend := float(visual_state.get("target_trend",0))
	text_native(Vector2(451,234), "升" if trend>.01 else ("降" if trend<-.01 else "稳"), ink)
	# Keep the entire shoe and bellows base visible above this bottom rail.
	draw_style_box(_gauge_panel(wood, ink),Rect2(42,562,928,36))
	draw_rect(Rect2(150,570,646,20),ink)
	draw_rect(Rect2(152,572,roundf(642*brew),16),Color("80a277"))
	draw_line(Vector2(602,564),Vector2(602,594),paper,4)
	text_native(Vector2(31,296),"炼制",paper)
	text_native(Vector2(408,296),"七成成炉",paper)

func _gauge_panel(fill: Color, edge: Color) -> StyleBoxFlat:
	var panel := StyleBoxFlat.new()
	panel.bg_color = fill
	panel.border_color = edge
	panel.set_border_width_all(4)
	panel.set_corner_radius_all(4)
	return panel
