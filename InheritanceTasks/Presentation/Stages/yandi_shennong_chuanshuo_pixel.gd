extends HeritagePixelCanvas

const ART := "res://InheritanceTasks/Art/Pixel/v1/runtime/yandi_shennong_chuanshuo/"
const V2 := "res://InheritanceTasks/Art/Pixel/v2/runtime/shennong/"
const V3 := "res://InheritanceTasks/Art/Pixel/v3/runtime/shennong/"
const PIXEL_FONT := preload("res://InheritanceTasks/Art/Pixel/v2/fonts/fusion-pixel-12px-proportional-zh_hans.ttf")
var _facing_left: bool = false
var _detail_camera_y: float = -1.0
var _detail_last_time: float = -1.0

func receive_visual_state(state: Dictionary) -> void:
	super.receive_visual_state(state)
	if artwork == null or not bool(artwork.properties.get("detailed_platform",false)): return
	var now := float(state.get("animation_time",0.0))
	var feet: Vector2 = state.get("feet",Vector2(75,500))
	if _detail_camera_y<0.0 or now<_detail_last_time:
		_detail_camera_y = maxf(0.0,feet.y-230.0)
	else:
		var dt := clampf(now-_detail_last_time,0.0,.25)
		var screen_y := (feet.y-_detail_camera_y)*2.0
		var desired := _detail_camera_y
		if screen_y<190.0: desired=feet.y-95.0
		elif screen_y>470.0: desired=feet.y-235.0
		_detail_camera_y = move_toward(_detail_camera_y,maxf(0.0,desired),dt*180.0)
		# A long render gap or a quick climb must not clip the head behind
		# the tutorial strip while the camera eases toward its new height.
		_detail_camera_y = minf(_detail_camera_y,maxf(0.0,feet.y-100.0))
	_detail_last_time = now

func paint() -> void:
	if bool(artwork.properties.get("detailed_platform",false)):
		paint_detailed_route()
		return
	if artwork.version >= 2:
		paint_native_route()
		return
	var part := maxi(0,[&"forest",&"creek",&"ridge"].find(StringName(visual_state.get("section",&"forest"))))
	paint_asset(ART + "background-%d.png" % part, Rect2(0,0,1000,600))
	var camera := float(visual_state.get("camera_x", 0.0))
	var player: Vector2 = visual_state.get("position", Vector2(60,456))
	var materials := ["forest", "creek", "ridge"]
	for platform: Rect2 in visual_state.get("platforms", []):
		var rect := Rect2(platform.position-Vector2(camera,0),platform.size)
		if rect.end.x < 0 or rect.position.x > 1000: continue
		var region := clampi(int(platform.position.x / 2600.0),0,2)
		var tile := asset(ART + str(materials[region]) + ".png")
		if tile == null: continue
		# The first texel is the exact standing surface. The rest extends down.
		for x: int in range(int(rect.position.x),int(rect.end.x),96):
			var width := minf(96,rect.end.x-x)
			draw_texture_rect_region(tile,Rect2(x,rect.position.y,width,16),Rect2(0,0,width,16))
			for y: int in range(int(rect.position.y)+16,int(rect.end.y),48):
				var height := minf(48,rect.end.y-y)
				draw_texture_rect_region(tile,Rect2(x,y,width,height),Rect2(0,16,width,height))
	for rock: Rect2 in visual_state.get("rocks", []):
		var rect := Rect2(rock.position-Vector2(camera,0),rock.size)
		if rect.end.x < 0 or rect.position.x > 1000: continue
		paint_asset(ART+"rock.png",rect)
		if rock.position.x-player.x > 0 and rock.position.x-player.x < 320:
			var pulse := 2.0 + sin(decoration_time()*5.0)*1.5
			draw_line(rect.position+Vector2(5,-9),rect.position+Vector2(10,-15-pulse),Color("ffd48e"),2)
	for branch: Rect2 in visual_state.get("branches", []):
		paint_asset(ART+"branch.png",Rect2(branch.position-Vector2(camera,0),branch.size))
	var checkpoint: Vector2 = visual_state.get("checkpoint",Vector2(60,456))
	paint_asset(ART+"marker.png",Rect2(checkpoint+Vector2(-camera-16,-16),Vector2(25,60)))
	var goal: Rect2 = visual_state.get("goal",Rect2(8150,85,120,120))
	paint_asset(ART+"marker.png",Rect2(goal.position+Vector2(20-camera,15),Vector2(50,105)))
	var feet: Vector2 = visual_state.get("feet",player+Vector2(15,44))
	var pose := StringName(visual_state.get("pose", "idle"))
	# Atlas anchor is (24,62); visible shoes touch the existing collision feet.
	paint_avatar(Rect2(feet-Vector2(camera+24,62),Vector2(48,64)),pose)

func paint_native_route() -> void:
	var root := V3 if artwork.version >= 3 else V2
	var part := maxi(0, [&"forest", &"creek", &"ridge"].find(StringName(visual_state.get("section", &"forest"))))
	paint_native(root + "background-%d.png" % part, Vector2.ZERO)
	# One camera quantization is shared by every foreground object. Tile
	# samples stay tied to world coordinates, so scrolling cannot animate them.
	var camera := floorf(float(visual_state.get("camera_x", 0.0)) / 2.0)
	for platform: Rect2 in visual_state.get("platforms", []):
		paint_ground(platform, camera)
	var player: Vector2 = visual_state.get("position", Vector2(60,456))
	for rock: Rect2 in visual_state.get("rocks", []):
		var p := Vector2(floorf(rock.position.x / 2) - camera, floorf(rock.position.y / 2))
		if p.x < -16 or p.x > 500: continue
		# Each route hazard has its own native-size rock, with no stretching.
		var footprint := Vector2i(roundi(rock.size.x / 2.0), roundi(rock.size.y / 2.0))
		paint_native(root + "rock-%dx%d.png" % [footprint.x, footprint.y], p)
		if rock.position.x > player.x and rock.position.x - player.x < 320:
			draw_line((p + Vector2(7,-7)) * 2, (p + Vector2(7,-3)) * 2, Color("f3ca67"), 2)
			draw_rect(Rect2((p + Vector2(7,-1)) * 2, Vector2(2,2)), Color("f3ca67"))
	for branch: Rect2 in visual_state.get("branches", []):
		var left := int(floorf(branch.position.x / 2.0))
		var right := int(ceilf(branch.end.x / 2.0))
		var top := floorf(branch.position.y / 2.0)
		for x in range(left, right, 16):
			paint_native(root + "branch.png", Vector2(x - camera, top), Rect2(0,0,mini(16,right-x),11))
		if branch.end.x > player.x and branch.position.x - player.x < 650:
			var hint := Vector2(left-camera,top-18)
			draw_rect(Rect2(hint*2,Vector2(72,16)*2),Color("f4dfad"))
			draw_string(PIXEL_FONT,(hint+Vector2(5,12))*2,"低枝 轻点跳",HORIZONTAL_ALIGNMENT_LEFT,-1,24,Color("44313b"))
	var checkpoint: Vector2 = visual_state.get("checkpoint",Vector2(60,456))
	paint_native(root + "marker.png", Vector2(floorf(checkpoint.x / 2)-camera-5, floorf((checkpoint.y+44) / 2)-32))
	var goal: Rect2 = visual_state.get("goal",Rect2(8150,85,120,120))
	paint_native(root + "marker.png", Vector2(floorf(goal.position.x/2)-camera+12, floorf(goal.end.y/2)-32))
	var velocity: Vector2 = visual_state.get("velocity",Vector2.ZERO)
	if absf(velocity.x)>1.0: _facing_left = velocity.x < 0.0
	var feet: Vector2 = visual_state.get("feet",player+Vector2(15,44))
	var foot_pixel := Vector2(floorf(feet.x/2)-camera, floorf(feet.y/2))
	var picture := avatar_texture(StringName(visual_state.get("pose", "idle")))
	if picture != null:
		draw_set_transform(foot_pixel * 2.0,0.0,Vector2(-1.0 if _facing_left else 1.0,1.0))
		draw_texture_rect(picture,Rect2(-20,-48,40,48),false)
		draw_set_transform(Vector2.ZERO)

func paint_ground(platform: Rect2, camera: float) -> void:
	var left := int(floorf(platform.position.x / 2.0))
	var right := int(ceilf(platform.end.x / 2.0))
	var top := int(floorf(platform.position.y / 2.0))
	var bottom := int(ceilf(platform.end.y / 2.0))
	if right-camera < 0 or left-camera > 500: return
	var region := clampi(int(platform.position.x/2600.0),0,2)
	var root := V3 if artwork.version >= 3 else V2
	var tile := asset(root + ["forest","creek","ridge"][region] + ".png")
	if tile == null: return
	var x := maxi(left,int(camera)-32)
	while x < mini(right,int(camera)+532):
		var sx := posmod(x,32)
		var width := mini(32-sx,right-x)
		draw_texture_rect_region(tile,Rect2((x-camera)*2,top*2,width*2,8),Rect2(sx,0,width,4))
		var y := top+4
		while y < mini(bottom,300):
			var sy := posmod(y,28)+4
			var height := mini(32-sy,bottom-y)
			draw_texture_rect_region(tile,Rect2((x-camera)*2,y*2,width*2,height*2),Rect2(sx,sy,width,height))
			y += height
		x += width

func paint_detailed_route() -> void:
	var part := maxi(0,[&"forest",&"creek",&"ridge"].find(StringName(visual_state.get("section",&"forest"))))
	paint_asset(V3+"background-%d.png"%part,Rect2(0,0,1000,600))
	var player: Vector2 = visual_state.get("position",Vector2(60,456))
	var camera := Vector2(maxf(0.0,player.x-180.0),maxf(0.0,_detail_camera_y)).floor()
	for platform: Rect2 in visual_state.get("platforms",[]):
		paint_detailed_ground(platform,camera)
	for rock: Rect2 in visual_state.get("rocks",[]):
		var dst := Rect2((rock.position-camera)*2.0,rock.size*2.0)
		if dst.end.x<0 or dst.position.x>1000:continue
		var footprint := Vector2i(roundi(rock.size.x/2),roundi(rock.size.y/2))
		paint_asset(V3+"rock-%dx%d.png"%[footprint.x,footprint.y],dst)
		if rock.position.x>player.x and rock.position.x-player.x<320:
			draw_line(dst.position+Vector2(14,-15),dst.position+Vector2(14,-7),Color("f3ca67"),3)
	for branch: Rect2 in visual_state.get("branches",[]):
		var dst := Rect2((branch.position-camera)*2.0,branch.size*2.0)
		if dst.end.x<0 or dst.position.x>1000:continue
		var texture := asset(V3+"branch.png")
		if texture!=null:
			for x in range(0,ceili(branch.size.x),32):
				var width := minf(32,branch.size.x-x)
				draw_texture_rect_region(texture,Rect2(dst.position+Vector2(x*2,0),Vector2(width*2,44)),Rect2(0,0,width,22))
		if branch.end.x>player.x:
			var hint := Vector2(clampf(dst.position.x,20,800),maxf(72,dst.position.y-36))
			draw_rect(Rect2(hint,Vector2(168,30)),Color("f4dfad"))
			draw_string(PIXEL_FONT,hint+Vector2(8,24),"低枝 轻点跳",HORIZONTAL_ALIGNMENT_LEFT,-1,24,Color("44313b"))
	var checkpoint: Vector2 = visual_state.get("checkpoint",Vector2(60,456))
	paint_asset(V3+"marker.png",Rect2((checkpoint+Vector2(-12,-20)-camera)*2.0,Vector2(72,128)))
	var goal: Rect2 = visual_state.get("goal",Rect2(8150,85,120,120))
	paint_asset(V3+"marker.png",Rect2((goal.position+Vector2(20,56)-camera)*2.0,Vector2(72,128)))
	var velocity: Vector2 = visual_state.get("velocity",Vector2.ZERO)
	if absf(velocity.x)>1:_facing_left=velocity.x<0
	var feet: Vector2 = visual_state.get("feet",player+Vector2(15,44))
	var picture := avatar_texture(StringName(visual_state.get("pose","idle")))
	if picture!=null:
		# The visible body is 60x88 pixels, matching the same 2x transform of
		# the existing 30x44 collision. Master pixels bypass the old 500px raster.
		draw_set_transform(((feet-camera)*2.0).round(),0.0,Vector2(-1.0 if _facing_left else 1.0,1.0))
		draw_texture_rect(picture,Rect2(-40,-96,80,96),false)
		draw_set_transform(Vector2.ZERO)

func paint_detailed_ground(platform: Rect2, camera: Vector2) -> void:
	var left := maxi(floori(platform.position.x),floori(camera.x)-64)
	var right := mini(ceili(platform.end.x),ceili(camera.x)+564)
	if left>=right:return
	var material := clampi(int(platform.position.x/2600),0,2)
	var tile := asset(V3+["forest","creek","ridge"][material]+".png")
	if tile==null:return
	var x:=left
	while x<right:
		var sx:=posmod(x,64)
		var width:=mini(64-sx,right-x)
		draw_texture_rect_region(tile,Rect2((Vector2(x,platform.position.y)-camera)*2,Vector2(width*2,16)),Rect2(sx,0,width,8))
		var y:=maxi(floori(platform.position.y)+8,floori(camera.y))
		while y<mini(ceili(platform.end.y),ceili(camera.y)+300):
			var sy:=posmod(y,56)+8
			var height:=mini(64-sy,ceili(platform.end.y)-y)
			draw_texture_rect_region(tile,Rect2((Vector2(x,y)-camera)*2,Vector2(width*2,height*2)),Rect2(sx,sy,width,height))
			y+=height
		x+=width
