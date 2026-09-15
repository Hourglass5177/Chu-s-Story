extends HeritagePixelCanvas

const Pattern := preload("res://InheritanceTasks/Data/paper_cut_pattern.gd")
const ART := "res://InheritanceTasks/Art/Pixel/v3/runtime/paper/"
const NEW_PAPER := "res://InheritanceTasks/Art/Pixel/v3/runtime/paper/pattern.png"
var _detail_anchors: Dictionary = {}

func paint() -> void:
	paint_asset(ART+"background.png",Rect2(0,0,1000,600))
	var paper := asset(NEW_PAPER)
	if paper != null: draw_texture_rect(paper,Pattern.PAPER_RECT,false)
	var paths: Array = visual_state.get("contours",[])
	var current := int(visual_state.get("segment",0))
	for i: int in paths.size():
		if i < current:
			draw_colored_polygon(paths[i],Color("44362f"))
			if i == current-1 and float(visual_state.get("detached_time",0.0)) > 0.0:
				var age := .6-float(visual_state.detached_time)
				var falling: PackedVector2Array = paths[i].duplicate()
				for p: int in falling.size(): falling[p] += Vector2(6*age,50*age*age)
				draw_colored_polygon(falling,Color(.73,.24,.23,1.0-age/.6))
		else:
			draw_colored_polygon(paths[i],Color("b53121"))
			draw_polyline(paths[i],Color("da866b"),2)
	if current < paths.size():
		var path: PackedVector2Array = paths[current]
		draw_polyline(path,Color("e9be79"),3)
		draw_polyline(Pattern.prefix(path,float(visual_state.get("cut_distance",0))),Color("332921"),5)
		draw_circle(path[0],8,Color("ffe1a0"))
		var point: Vector2 = visual_state.get("pointer",path[0])
		var hands := asset(ART+str(avatar_id)+"-hand.png")
		if hands != null:
			# The crop starts at the blade tip, so it is the actual input point.
			if _detail_anchors.is_empty():
				_detail_anchors = JSON.parse_string(FileAccess.get_file_as_string(ART+"detail-anchors.json"))
			var dimensions: Array = _detail_anchors.hand_display_sizes[str(avatar_id)]
			draw_texture_rect(hands,Rect2(point.round(),Vector2(dimensions[0],dimensions[1])),false)
		else: draw_circle(point,5,Color("f6dfb0"))
