extends HeritagePixelCanvas
const NEW_ART := "res://InheritanceTasks/Art/Pixel/v3/runtime/shenzhou/"
const RIVER_PROJECTION := 0.60
var _hint_font: Font = HeritageTelevisionStyle.pixel_font()

func paint() -> void:
	var new_background := asset(NEW_ART+"background.png")
	if new_background != null: draw_texture_rect(new_background,Rect2(0,0,1000,600),false)
	else: paint_background()
	var distance := float(visual_state.get("distance",0.0))
	var travel := float(visual_state.get("wake_distance",distance))
	for row: int in 14:
		var y := 115+fposmod(travel*RIVER_PROJECTION+row*39,450.0)
		for x: int in [360,640]: draw_line(Vector2(x,y),Vector2(x,y+16),Color(.81,.91,.83,.5),2)
	for obstacle: Dictionary in visual_state.get("obstacles",[]):
		var point := Vector2(220+int(obstacle.lane)*280,450-float(obstacle.gap)*RIVER_PROJECTION)
		var shape := asset(NEW_ART+("obstacle-boat-v4.png" if obstacle.kind=="boat" else "obstacle-driftwood.png"))
		# Preserve the prop's native aspect. The ceremonial tower is decoration;
		# its lower raft and the ordinary hull occupy the water plane.
		var hull := Vector2(112,102) if obstacle.kind=="boat" else Vector2(118,66)
		if shape != null and obstacle.kind=="boat": hull.y=hull.x*shape.get_height()/float(shape.get_width())
		draw_ellipse_marker(point,Vector2(60,hull.y*.47),Color(.12,.22,.20,.4))
		if shape != null: draw_texture_rect(shape,Rect2((point-hull*.5).round(),hull),false)
		else:
			# Explicit prototype obstacle until its separate generated prop is in.
			draw_colored_polygon(PackedVector2Array([point+Vector2(-56,-16),point+Vector2(52,-16),point+Vector2(36,20),point+Vector2(-38,20)]),Color("826348"))
			for rib: int in 5: draw_line(point+Vector2(-35+rib*17,-13),point+Vector2(-28+rib*14,14),Color("b79a65"),3)
	var lane := float(visual_state.get("lane",1.0))
	var origin := Vector2(220+lane*280,474)
	var boat := asset(NEW_ART+"boat.png")
	draw_ellipse_marker(origin-Vector2(0,24),Vector2(60,26),Color(.12,.22,.20,.4))
	for i: int in 4:
		var age := fposmod(travel*.12+i*13,55.0)
		draw_arc(origin+Vector2(0,age),30+age*.5,.1,PI-.1,18,Color(.81,.92,.84,.48*(1-age/60.0)),2)
	if boat != null: draw_texture_rect(boat,Rect2((origin-Vector2(84,224)).round(),Vector2(168,224)),false)
	if bool(visual_state.get("narrow",false)):
		draw_rect(Rect2(377,97,246,45),Color("f0d896"))
		draw_string(_hint_font,Vector2(402,127),"看空道换向",HORIZONTAL_ALIGNMENT_LEFT,-1,24,Color("453b2e"))
	# The blogger stays on shore; no rower is invented aboard the ritual boat.
	if distance < 250.0 or distance > float(visual_state.get("route_length",7200))-190.0: paint_avatar(Rect2(20,94,112,160),&"wave")

func draw_ellipse_marker(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i: int in 32: points.append(center+Vector2(cos(i*TAU/32),sin(i*TAU/32))*radii)
	draw_colored_polygon(points,color)
