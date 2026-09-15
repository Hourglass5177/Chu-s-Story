extends HeritagePixelCanvas

const BUBBLES := "res://InheritanceTasks/Art/Pixel/v1/runtime/craft/tianmen_tang_su-bubbles.png"
const GENERATED_BUBBLES := "res://InheritanceTasks/Art/Pixel/v3/runtime/tianmen_tang_su/bubbles.png"
# Visually checked atlas: 0 is a thick-walled embryo, 4 is deformed,
# and 5 is the round formed bubble. Size and the existing result labels
# distinguish an underblown embryo from an overblown, misshapen one.
const OUTCOME_MATERIALS := {"偏小": 0, "合适": 5, "过大": 4}
var _anchors: Dictionary = {}

func paint() -> void:
	if artwork.version >= 3 and bool(artwork.properties.get("generated_sugar", false)):
		paint_generated()
		return
	paint_background()
	var phase := int(visual_state.get("blow_phase", 0))
	var radius := float(visual_state.get("radius", 0.0))
	var avatar_rect := Rect2(45, 165, 365, 365)
	paint_avatar(avatar_rect, &"hold" if phase == 1 else action())
	var center := Vector2(650, 390)
	var bubble_scale := maxf(8.0,radius*155.0)/68.0
	var bubble_rect := Rect2(center-Vector2(88,88)*bubble_scale,Vector2.ONE*160*bubble_scale)
	var picture := asset(BUBBLES)
	var material := clampi(int(radius * 4.0), 0, 3)
	var outcomes: Array = visual_state.get("outcomes", [])
	if phase == 3 and not outcomes.is_empty():
		material = int(OUTCOME_MATERIALS.get(str(outcomes[-1]), material))
	# Tube is a separate connecting layer, so the membrane can really keep growing after release.
	if _anchors.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://InheritanceTasks/Art/Pixel/v1/runtime/craft/anchors.json"))
		if data is Dictionary: _anchors = data
	var avatar_frame := 2 if phase == 1 else (3 if phase == 2 else (5 if material == 5 else (4 if phase == 3 else 0)))
	var tips: Array = _anchors.get("tube_tip",{}).get(str(avatar_id),[])
	var tip := Vector2(119,80)
	if tips.size() > avatar_frame: tip = Vector2(tips[avatar_frame][0],tips[avatar_frame][1])
	var tube_from := avatar_rect.position+tip*avatar_rect.size/128.0
	var tube_to := bubble_rect.position+Vector2(4,92)*bubble_scale
	draw_line(tube_from,tube_to,Color("54301d"),7)
	draw_line(tube_from-Vector2(0,2),tube_to-Vector2(0,2),Color("cba36a"),2)
	if picture != null:
		draw_texture_rect_region(picture,bubble_rect,Rect2(material * 160, 0, 160, 160))
	var tray_items := get_outcome_draw_items()
	for i: int in tray_items.size():
		draw_rect(Rect2(490 + i * 145, 502, 122, 43), Color("d5ae73"))
		if picture != null:
			draw_texture_rect_region(picture, tray_items[i].destination, tray_items[i].source)

func get_outcome_draw_items() -> Array[Dictionary]:
	var outcomes: Array = visual_state.get("outcomes", [])
	var radii: Array = visual_state.get("outcome_radii", [])
	var targets: Array = visual_state.get("outcome_targets", [])
	var items: Array[Dictionary] = []
	for i: int in mini(3, outcomes.size()):
		var outcome := str(outcomes[i])
		var target: Vector2 = targets[i] if i < targets.size() else Vector2(0.6, 0.74)
		var reference_radius := maxf(0.001, (target.x + target.y) * 0.5)
		var final_radius := float(radii[i]) if i < radii.size() else reference_radius
		var side := roundf(clampf(67.0 * final_radius / reference_radius, 28.0, 96.0))
		items.append({"outcome": outcome, "radius": final_radius,
			"source": Rect2(int(OUTCOME_MATERIALS.get(outcome, 0)) * 160, 0, 160, 160),
			"destination": Rect2(551 + i * 145 - side * 0.5, 541 - side, side, side)})
		if artwork != null and bool(artwork.properties.get("generated_sugar", false)):
			items[-1].destination.position.x = 432 + i * 178 - side * 0.5
			var source_side := int(artwork.properties.get("bubble_frame_size", 160))
			items[-1].source = Rect2(int(OUTCOME_MATERIALS.get(outcome, 0)) * source_side, 0, source_side, source_side)
	return items

func paint_generated() -> void:
	paint_background()
	var phase := int(visual_state.get("blow_phase", 0))
	var radius := float(visual_state.get("radius", 0.0))
	var outcomes: Array = visual_state.get("outcomes", [])
	var motion := action()
	if phase == 3 and not outcomes.is_empty() and str(outcomes[-1]) == "过大": motion = &"over"
	paint_avatar(Rect2(70,90,400,400), motion)
	var center := Vector2(590,330)
	var scale_factor := maxf(8.0,radius*155.0)/68.0
	var bubble_rect := Rect2(center-Vector2(80,80)*scale_factor,Vector2.ONE*160*scale_factor)
	var picture := asset(GENERATED_BUBBLES)
	var material := clampi(int(radius*4.0),0,3)
	if phase == 3 and not outcomes.is_empty(): material = int(OUTCOME_MATERIALS.get(str(outcomes[-1]),material))
	# The generated tube ends at a registered anchor; the short neck connects to
	# the continuously expanding membrane, independently of the character pose.
	var neck := bubble_rect.position+Vector2(7,78)*scale_factor
	if neck.x > 462.0:
		draw_line(Vector2(461,326),neck,Color("693e32"),6)
		draw_line(Vector2(461,324),neck-Vector2(0,2),Color("dfae65"),2)
	if picture != null:
		var source_side := int(artwork.properties.get("bubble_frame_size", 160))
		draw_texture_rect_region(picture,bubble_rect,Rect2(material*source_side,0,source_side,source_side))
	paint_foreground()
	if picture != null:
		for item: Dictionary in get_outcome_draw_items():
			draw_texture_rect_region(picture,item.destination,item.source)
