extends HeritagePixelCanvas

const ART := "res://InheritanceTasks/Art/Pixel/v1/runtime/xingshan_min_ge/"
const V3 := "res://InheritanceTasks/Art/Pixel/v3/runtime/xingshan_min_ge/"

func paint() -> void:
	var time := float(visual_state.get("music_time",0.0))
	var part := clampi(int(time/10.6),0,3)
	var art_root := V3 if artwork.version >= 3 else ART
	paint_asset(art_root+"background-%d.png"%part,Rect2(0,0,1000,600))
	# A narrow crossfade at the scene boundary preserves continuous travel.
	if part > 0 and fmod(time,10.6)<1.0:
		var previous := asset(art_root+"background-%d.png"%(part-1))
		if previous != null: draw_texture_rect(previous,Rect2(0,0,1000,600),false,Color(1,1,1,1.0-fmod(time,10.6)))
	for gate: Dictionary in visual_state.get("gates",[]):
		var x := 280+(float(gate.time)-time)*160
		if x < -80 or x>1100: continue
		var y := float(gate.y)
		paint_asset(art_root+"gate-bottom.png",Rect2(x-70,y+90,140,maxf(1,600-y-90)))
		paint_asset(art_root+"gate-top.png",Rect2(x-65,0,130,maxf(1,y-90)))
		var color := Color("c9e5b5") if bool(gate.get("hit",false)) else Color("f4d998")
		draw_arc(Vector2(x,y),35,-PI*.5,PI*.5,20,color,2)
	var bird := Vector2(280,float(visual_state.get("bird_y",300.0)))
	var pose := str(visual_state.get("bird_pose","glide"))
	if artwork.version >= 3:
		paint_generated_birds(bird,pose)
		if time<2.5 or time>40.5:
			paint_avatar(Rect2(45,370,112,160),&"ready" if time<2.5 else &"wave")
		return
	var frame := 2
	match pose:
		"flap": frame = int(animation_time()*9)%2
		"descend": frame = 3
		"miss": frame = 4
		"recover": frame = 5
		"land": frame = 6 if fmod(animation_time(),1.0)<0.5 else 7
	var atlas := asset(ART+"bird.png")
	if atlas != null:
		draw_texture_rect_region(atlas,Rect2(bird-Vector2(36,36),Vector2(64,64)),Rect2((frame%4)*64,(frame/4)*64,64,64))
		for follower: Dictionary in visual_state.get("followers",[]):
			var f := follower_frame(follower,bool(visual_state.get("reduced_motion",false)))
			var position: Vector2 = follower.position
			draw_texture_rect_region(atlas,Rect2(position-Vector2(15,15),Vector2(30,30)),Rect2((f%4)*64,(f/4)*64,64,64),Color(0.75,0.82,0.78,.85))
	if time<2.5 or time>40.5:
		paint_avatar(Rect2(45,370,112,160),&"ready" if time<2.5 else &"wave")

func follower_frame(follower: Dictionary, reduce_motion: bool = false) -> int:
	match str(follower.get("pose","glide")):
		"miss": return 4
		"recover": return 5
		"descend": return 3
		"flap": return 2 if reduce_motion else posmod(floori(float(follower.get("wing_time",0.0))*9.0),2)
	return 2

func generated_bird_frame(pose: String, clock: float, reduce_motion: bool = false) -> int:
	match pose:
		"flap": return 6 if reduce_motion else posmod(floori(clock*12.0),6)
		"descend": return 7
		"miss": return 8
		"recover": return 9
		"land": return 10 if fmod(clock,1.0)<.25 else 11
	return 6

func paint_generated_birds(bird: Vector2, pose: String) -> void:
	var reduced := bool(visual_state.get("reduced_motion",false))
	var frame := generated_bird_frame(pose,animation_time(),reduced)
	var atlas := asset(V3+"bird.png")
	if atlas != null:
		draw_texture_rect_region(atlas,Rect2(bird.round()-Vector2(32,32),Vector2(64,64)),Rect2((frame%4)*128,(frame/4)*128,128,128))
	var small := asset(V3+"followers.png")
	if small == null: return
	for follower: Dictionary in visual_state.get("followers",[]):
		var f := generated_bird_frame(str(follower.get("pose","glide")),float(follower.get("wing_time",0.0)),reduced)
		var position: Vector2 = follower.position
		draw_texture_rect_region(small,Rect2(position.round()-Vector2(14,14),Vector2(30,30)),Rect2((f%4)*128,(f/4)*128,128,128))
