-- Whole-body working-cycle study. Fixed-length two-bone limbs, visible neck,
-- three-quarter working head, two grounded feet and a hinged leather bellows.
local root=app.params.root or "F:/Documents/楚物志"
local D=dofile(root.."/tools/aseprite/pixel_drawing.lua")
local out=root.."/InheritanceTasks/Art/Pixel/v2/review/workshop-motion-r3"
app.fs.makeAllDirectories(out)
local ref=assert(app.open(root.."/InheritanceTasks/Art/Pixel/v2/review/avatar-identity-r2/travel-redraw.aseprite"))
local palette=ref.palettes[1]
local actor=Sprite(160,190,ColorMode.INDEXED);actor:setPalette(palette);actor.transparentColor=0
actor:deleteLayer(actor.layers[1]);actor.gridBounds=Rectangle(0,0,1,1)
ref:close()
for i=2,24 do actor:newEmptyFrame(i) end
for _,fr in ipairs(actor.frames) do fr.duration=.05 end
local ORIGIN={90,60}
local function image() return Image(160,190,ColorMode.INDEXED) end
local function p(im,pts,c)
  local a={};for _,v in ipairs(pts) do a[#a+1]={v[1]-ORIGIN[1],v[2]-ORIGIN[2]} end;D.poly(im,a,c)
end
local function r(im,x,y,w,h,c) D.rect(im,x-90,y-60,w,h,c) end
local function l(im,x,y,a,b,c,w) D.line(im,x-90,y-60,a-90,b-60,c,w) end
local function e(im,x,y,w,h,c) D.ellipse(im,x-90,y-60,w,h,c) end
local function round(v) return math.floor(v+.5) end
local function limb(im,a,b,width,base,light)
  local dx,dy=b[1]-a[1],b[2]-a[2];local dist=math.sqrt(dx*dx+dy*dy)
  local nx,ny=-dy/dist,dx/dist
  local function strip(w,col)
    p(im,{{a[1]+nx*w,a[2]+ny*w},{b[1]+nx*w,b[2]+ny*w},
      {b[1]-nx*w,b[2]-ny*w},{a[1]-nx*w,a[2]-ny*w}},col)
    e(im,a[1]-w,a[2]-w,w*2+1,w*2+1,col);e(im,b[1]-w,b[2]-w,w*2+1,w*2+1,col)
  end
  strip(width/2,1);strip(width/2-1,base)
  if light then l(im,a[1]+nx,a[2]+ny,b[1]+nx,b[2]+ny,light) end
end
local function ik(a,b,u,v,side)
  local dx,dy=b[1]-a[1],b[2]-a[2]
  local distance=math.sqrt(dx*dx+dy*dy)
  assert(distance<u+v+.5,"unreachable contact in authored pose")
  local along=(u*u-v*v+distance*distance)/(2*distance)
  local lift=math.sqrt(math.max(0,u*u-along*along))*side
  return {round(a[1]+dx/distance*along-dy/distance*lift),
          round(a[2]+dy/distance*along+dx/distance*lift)}
end
local function cel(name,im,k)
  local layer=nil;for _,a in ipairs(actor.layers) do if a.name==name then layer=a end end
  if not layer then layer=actor:newLayer();layer.name=name end
  actor:newCel(layer,k,im,Point(0,0))
end

-- A separately redrawn working head: facing the apparatus, not the viewer.
-- Skin, eye, hair and hat palette values remain those of the identity study.
local head=Image(82,76,ColorMode.INDEXED)
local function hp(a,c) D.poly(head,a,c) end
local function hl(x,y,a,b,c,w) D.line(head,x,y,a,b,c,w) end
local function hr(x,y,w,h,c) D.rect(head,x,y,w,h,c) end
local function he(x,y,w,h,c) D.ellipse(head,x,y,w,h,c) end
-- Back hair and two low tied sections, one partly behind the neck.
-- Explicit usable outline below, with no procedurally changed face per frame.
hp({{19,25},{32,22},{51,27},{61,37},{57,51},{47,62},{33,66},{17,61},{13,50},{14,35}},2)
hp({{18,32},{24,27},{35,25},{49,29},{56,37},{53,48},{45,58},{33,63},{19,58},{16,49}},3)
hp({{15,51},{23,50},{29,55},{27,62},{22,66},{16,64},{12,64},{13,60},{9,60},{11,55}},2)
hp({{16,52},{22,52},{26,56},{24,61},{22,63},{18,61},{16,63},{14,60},{16,57},{12,59},{13,55}},4)
hl(17,54,18,58,5);hl(24,55,23,58,3)
hp({{33,58},{39,57},{44,61},{47,60},{46,64},{41,67},{35,66},{31,63}},2)
hp({{34,59},{38,59},{42,62},{44,63},{40,65},{36,64},{33,62}},4)
-- Cheek, jaw, nose and ear form one three-quarter silhouette.
hp({{28,27},{43,26},{55,30},{62,37},{63,43},{67,46},{66,49},{63,50},{63,55},{60,60},{53,63},{43,63},{34,59},{27,53},{22,44},{23,35}},1)
hp({{29,28},{43,27},{54,31},{60,37},{61,44},{65,46},{65,48},{61,49},{61,54},{59,58},{52,61},{44,62},{35,58},{29,52},{24,44},{25,35}},6)
hp({{24,40},{28,49},{35,56},{44,61},{39,60},{32,57},{27,52},{23,45}},7)
he(20,41,10,12,2);he(21,42,8,10,6)
hl(24,44,26,45,7);hl(26,45,25,48,7);hr(23,48,1,2,7)
hr(37,53,5,1,8);hr(39,54,3,1,8)
hl(62,47,64,47,7);hl(56,56,59,56,22);hr(60,55,1,1,22)
-- Swept asymmetrical bangs, ash grey with grouped rose highlights.
hp({{18,31},{22,25},{30,22},{38,25},{43,28},{51,29},{57,31},{62,35},{63,40},{61,43},{58,39},{53,40},{48,36},{44,37},{39,34},{35,35},{30,31},{28,37},{25,41},{22,44},{20,42},{20,37},{17,40}},2)
hp({{20,30},{24,26},{30,24},{36,26},{41,29},{48,31},{54,31},{59,34},{61,38},{59,37},{57,37},{53,38},{49,34},{44,35},{40,32},{35,33},{30,29},{27,34},{24,38},{22,41},{22,36},{19,38}},3)
hp({{23,28},{27,26},{28,29},{25,33},{24,36},{22,38},{22,33}},4)
hp({{30,25},{34,27},{37,30},{40,32},{36,32},{31,29},{29,31}},4)
hp({{42,30},{47,32},{51,33},{55,36},{53,37},{49,34},{45,34}},4)
hl(24,28,25,30,5);hl(32,27,34,29,5);hl(46,32,49,33,5)
-- Bucket hat follows the head orientation; the front brim points toward work.
hp({{13,21},{17,13},{24,7},{33,2},{39,1},{47,3},{55,7},{64,10},{68,15},{69,23},{66,29},{70,34},{78,38},{76,41},{70,41},{63,38},{54,34},{46,32},{39,30},{31,27},{23,24},{17,25},{10,27},{7,25},{8,23}},1)
hp({{15,21},{19,13},{25,8},{34,3},{39,2},{46,4},{54,8},{63,11},{66,15},{67,22},{64,29},{68,35},{75,38},{75,39},{70,39},{64,36},{54,32},{47,30},{40,28},{32,25},{24,22},{18,23},{11,25},{9,24}},13)
hp({{56,9},{62,12},{65,16},{65,22},{62,28},{65,33},{69,36},{72,38},{68,37},{60,33},{59,28},{61,22},{61,17}},14)
hp({{22,13},{26,9},{34,5},{39,4},{44,5},{36,6},{30,9},{26,13},{24,16},{20,18}},15)
hp({{11,24},{18,21},{24,22},{22,24},{18,24},{13,26}},14)
-- Original curl at the front rim, adapted to the new view.
hp({{39,29},{41,27},{46,27},{49,29},{49,32},{47,33},{44,32},{44,30},{41,30}},2)
hp({{42,28},{45,28},{47,30},{47,31},{45,31},{44,29},{42,30}},4)
-- Near eye is fully readable; far eye is foreshortened, both look at the work.
hp({{43,44},{45,42},{49,42},{52,44},{52,48},{50,51},{46,51},{44,49}},9)
hp({{48,43},{51,44},{51,48},{50,51},{47,50},{47,46}},10)
hr(48,46,2,4,11);hr(48,49,2,1,12);hr(49,44,1,1,9)
hl(42,44,45,41,1);hl(45,41,49,41,1);hl(49,41,52,43,1)
hp({{60,43},{62,43},{63,45},{63,48},{61,49},{60,47}},9)
hr(62,44,1,4,10);hr(62,45,1,2,11)
hl(60,42,62,42,2);hr(63,43,1,1,2)
hl(43,38,47,37,22);hl(47,37,50,38,22)

-- Shoulder/pelvis changes are authored key poses, not global whole-sprite bob.
local hx={0,-1,-2,-3,-3,-2,0,2,3,3,2,1}
local hy={0,0,-1,-1,-1,0,1,3,4,4,3,1}
local sx={0,-1,-3,-4,-4,-2,1,5,6,5,3,1}
local sy={0,-1,-2,-2,-2,-1,1,4,5,5,3,1}
local angle={-.02,-.08,-.19,-.30,-.33,-.30,-.19,-.05,0,0,-.005,-.012}
-- In-betweens derive from the authored 12 poses, never new independent images.
local function inbetween(values)
  local result={}
  for k=1,12 do
    result[#result+1]=values[k]
    result[#result+1]=(values[k]+values[k%12+1])*.5
  end
  return result
end
hx=inbetween(hx);hy=inbetween(hy);sx=inbetween(sx);sy=inbetween(sy);angle=inbetween(angle)
local data={schema_version=1,status="motion review; not user accepted",frame_ms=50,origin=ORIGIN,frames={}}
local footA={151,235};local footB={181,235}
for k=1,24 do
  local hip={round(163+hx[k]),round(201+hy[k])};local shoulder={round(165+sx[k]),round(164+sy[k])}
  local neck={shoulder[1]+1,shoulder[2]-9}
  local hinge={289,195}
  local grip={round(hinge[1]-95*math.cos(angle[k])),round(hinge[2]+95*math.sin(angle[k]))}
  local nearHand={grip[1]+2,grip[2]-1};local farHand={grip[1]-3,grip[2]-1}
  local nearShoulder={shoulder[1]+9,shoulder[2]+3}
  local farShoulder={shoulder[1]-7,shoulder[2]+5}
  local nearElbow=ik(nearShoulder,nearHand,24,24,1)
  local farElbow=ik(farShoulder,farHand,26,25,1)
  local kneeA=ik({hip[1]-7,hip[2]+1},footA,19,18,-1)
  local kneeB=ik({hip[1]+7,hip[2]+1},footB,19,18,-1)
  local im=image();e(im,137,238,64,7,19)
  cel("ground shadow fixed",im,k)
  im=image()
  limb(im,{hip[1]-7,hip[2]+1},kneeA,10,20,18);limb(im,kneeA,footA,9,20,18)
  limb(im,{hip[1]+7,hip[2]+1},kneeB,11,17,20);limb(im,kneeB,footB,10,17,20)
  p(im,{{145,232},{154,232},{156,236},{154,242},{137,242},{138,239},{146,237}},1)
  p(im,{{146,234},{152,234},{153,239},{141,240},{147,237}},2)
  l(im,143,239,152,239,18)
  p(im,{{176,232},{184,232},{188,237},{198,239},{198,242},{176,242},{175,239}},1)
  p(im,{{177,234},{183,234},{186,238},{194,240},{178,240}},2)
  l(im,181,239,190,239,18)
  cel("legs - distinct knees and fixed feet",im,k)
  im=image()
  -- Far arm is drawn behind the chest, maintaining both bone lengths.
  limb(im,farShoulder,farElbow,9,13,15)
  limb(im,farElbow,farHand,7,7,6)
  cel("far arm fixed lengths",im,k)
  im=image()
  local a,b=shoulder[1],shoulder[2];local u,v=hip[1],hip[2]
  p(im,{{a-12,b-5},{a+10,b-5},{a+18,b+5},{a+15,b+22},{u+16,v+8},{u+7,v+13},{u-15,v+9},{u-18,v-6},{a-17,b+8}},1)
  p(im,{{a-11,b-3},{a+9,b-3},{a+15,b+5},{a+12,b+23},{u+14,v+7},{u+6,v+10},{u-13,v+7},{u-15,v-6},{a-14,b+8}},13)
  p(im,{{a+9,b},{a+14,b+5},{a+11,b+23},{u+13,v+7},{u+7,v+9},{u+8,v-7}},14)
  p(im,{{a-9,b+9},{a+8,b+9},{u+13,v+8},{u+5,v+11},{u-13,v+8},{u-10,v-7}},16)
  p(im,{{a-7,b+11},{a+6,b+11},{u+10,v+6},{u+4,v+8},{u-10,v+6},{u-8,v-7}},17)
  l(im,a-7,b-1,a-7,b+13,16,2);l(im,a+5,b-1,a+6,b+13,16,2)
  p(im,{{u-8,v-10},{u+8,v-9},{u+8,v-2},{u+4,v+1},{u-6,v},{u-8,v-3}},20)
  l(im,u-7,v-9,u+6,v-8,18)
  l(im,u-11,v+4,u+9,v+6,20)
  -- Five visible skin pixels connect chin to collar; no pasted head overlap.
  p(im,{{neck[1]-4,neck[2]-5},{neck[1]+5,neck[2]-5},{neck[1]+6,b-3},{neck[1]+1,b+1},{neck[1]-5,b-3}},7)
  p(im,{{neck[1]-2,neck[2]-5},{neck[1]+4,neck[2]-5},{neck[1]+4,b-3},{neck[1]+1,b-1},{neck[1]-3,b-3}},6)
  p(im,{{a-9,b-4},{a-4,b-6},{a+1,b-1},{a+7,b-6},{a+12,b-3},{a+7,b+3},{a+1,b+5},{a-7,b+1}},16)
  p(im,{{a-7,b-4},{a-3,b-4},{a+1,b+1},{a+7,b-4},{a+9,b-3},{a+6,b+1},{a+1,b+3},{a-5,b}},17)
  l(im,a-4,b-2,a,b+1,18)
  cel("torso - shoulder hip axis and visible neck",im,k)
  im=image()
  im:drawImage(head,Point(round(neck[1]-44-90),round(neck[2]-64-60)))
  cel("three quarter working head anchored to neck",im,k)
  im=image()
  limb(im,nearShoulder,nearElbow,10,13,15)
  -- Rolled cuff lies just before the elbow, not floating on the forearm.
  local cuff={round(nearElbow[1]*.85+nearShoulder[1]*.15),round(nearElbow[2]*.85+nearShoulder[2]*.15)}
  limb(im,cuff,nearElbow,10,15,13)
  limb(im,nearElbow,nearHand,8,6,7)
  e(im,farHand[1]-4,farHand[2]-3,8,8,1);e(im,farHand[1]-3,farHand[2]-2,6,6,7)
  e(im,nearHand[1]-4,nearHand[2]-4,9,9,1);e(im,nearHand[1]-3,nearHand[2]-3,7,7,6)
  l(im,nearHand[1],nearHand[2],nearHand[1]+3,nearHand[2],7)
  l(im,nearHand[1]-1,nearHand[2]+2,nearHand[1]+2,nearHand[2]+2,7)
  cel("near arm and two contact hands",im,k)
  data.frames[#data.frames+1]={frame=k,phase=k<=10 and "draw_air" or (k<=18 and "press_air" or "recover"),
    shoulder=shoulder,hip=hip,neck=neck,near_shoulder=nearShoulder,near_elbow=nearElbow,near_hand=nearHand,
    far_shoulder=farShoulder,far_elbow=farElbow,far_hand=farHand,grip=grip,hinge=hinge,angle=angle[k],
    foot_a=footA,foot_b=footB,knee_a=kneeA,knee_b=kneeB}
end
actor:newTag(1,24).name="draw_press_recover"
local sl=actor:newSlice(Rectangle(0,0,160,190));sl.name="ground_anchor";sl.pivot=Point(73,182)
actor.data="R3 working posture: independent torso/hips/knees, 24+24 near arm and 26+25 far arm. Head is three-quarter facing work."
actor:saveAs(out.."/travel-work-cycle.aseprite")
actor:saveCopyAs(out.."/travel-work-cycle.png")
actor:close()
local f=assert(io.open(out.."/body-anchors.json","w"));f:write(json.encode(data));f:close()

-- Hinged leather bellows: fixed nozzle/base; lid rotation changes the pleats.
local bp=Palette(15);bp:setColor(0,Color{r=0,g=0,b=0,a=0})
local h={"2b2b36","4f3833","78523e","a16d49","c79360","e6bb82","3c424b","686b72","999892","463036","74504d","98655a","b5836b","cfa181"}
for i,x in ipairs(h) do bp:setColor(i,Color{r=tonumber(x:sub(1,2),16),g=tonumber(x:sub(3,4),16),b=tonumber(x:sub(5,6),16),a=255}) end
local bellows=Sprite(150,104,ColorMode.INDEXED);bellows:setPalette(bp);bellows.transparentColor=0;bellows:deleteLayer(bellows.layers[1])
for i=2,24 do bellows:newEmptyFrame(i) end;for _,fr in ipairs(bellows.frames) do fr.duration=.05 end
local bo={175,147}
local function bpnt(im,a,c) local v={};for _,x in ipairs(a) do v[#v+1]={x[1]-bo[1],x[2]-bo[2]} end;D.poly(im,v,c) end
local function blin(im,x,y,a,b,c,w) D.line(im,x-bo[1],y-bo[2],a-bo[1],b-bo[2],c,w) end
local function bcel(name,im,k)
  local layer=nil;for _,a in ipairs(bellows.layers) do if a.name==name then layer=a end end
  if not layer then layer=bellows:newLayer();layer.name=name end
  bellows:newCel(layer,k,im,Point(0,0))
end
for k=1,24 do
  local im=Image(150,104,ColorMode.INDEXED)
  -- Stationary stand and lower board.
  bpnt(im,{{218,213},{226,213},{224,241},{215,241}},1)
  bpnt(im,{{220,215},{224,215},{222,239},{218,239}},3)
  bpnt(im,{{282,207},{290,207},{296,237},{287,239}},1)
  bpnt(im,{{284,209},{289,209},{292,235},{289,237}},3)
  bpnt(im,{{211,211},{281,203},{297,211},{288,219},{213,224},{208,219}},1)
  bpnt(im,{{213,213},{281,205},{293,211},{286,216},{214,222},{210,218}},4)
  blin(im,217,220,285,215,5)
  -- Nozzle stays connected to the furnace and never follows the handle.
  bpnt(im,{{284,192},{318,196},{322,201},{320,205},{285,201}},1)
  bpnt(im,{{285,194},{317,198},{319,201},{317,203},{286,199}},7)
  blin(im,288,195,316,199,8)
  bcel("stationary lower board stand and nozzle",im,k)
  im=Image(150,104,ColorMode.INDEXED)
  local a=angle[k]
  local left={round(289-75*math.cos(a)),round(195+75*math.sin(a))}
  local back={left[1]+7,left[2]-7}
  -- Folded bag, distinct upper/lower edges. Pleats open in real geometry.
  bpnt(im,{{left[1],left[2]},{288,195},{288,214},{215,220},{210,left[2]+8}},1)
  bpnt(im,{{left[1]+2,left[2]+2},{286,197},{286,212},{217,218},{213,left[2]+8}},11)
  for fold=1,3 do
    local t=fold/4
    local yy=round(left[2]+(220-left[2])*t)
    local righty=round(196+(213-196)*t)
    bpnt(im,{{left[1]+1,yy-1},{286,righty-1},{285,righty+1},{left[1]+3,yy+2},{left[1]-1,yy+1}},10)
    blin(im,left[1]+4,yy-2,281,righty-2,12)
  end
  -- Hinge-to-handle board; only this assembly rotates.
  bpnt(im,{{back[1],back[2]},{281,187},{293,193},{289,199},{left[1],left[2]+5},{left[1]-3,left[2]+1}},1)
  bpnt(im,{{back[1],back[2]+2},{280,189},{289,193},{286,196},{left[1]+2,left[2]+2},{left[1],left[2]}},5)
  blin(im,back[1]+2,back[2]+3,279,191,6)
  blin(im,left[1]+2,left[2]+3,286,197,3,2)
  local grip=data.frames[k].grip
  bpnt(im,{{grip[1]-3,grip[2]-3},{left[1]+3,left[2]-2},{left[1]+4,left[2]+3},{grip[1]-3,grip[2]+3}},1)
  blin(im,grip[1]-2,grip[2],left[1]+2,left[2],4,3)
  blin(im,grip[1]-1,grip[2]-1,left[1]+1,left[2]-1,6)
  D.ellipse(im,284-bo[1],190-bo[2],8,9,7);D.ellipse(im,286-bo[1],192-bo[2],3,4,9)
  bcel("hinged lid handle and expanding leather folds",im,k)
end
bellows:newTag(1,24).name="draw_press_recover"
bellows.data="Illustrative hinged leather bellows, fixed nozzle. Not a verified Xia workshop equipment reconstruction."
bellows:saveAs(out.."/bellows-cycle.aseprite");bellows:saveCopyAs(out.."/bellows-cycle.png");bellows:close()
data.bellows_origin=bo
f=assert(io.open(out.."/body-anchors.json","w"));f:write(json.encode(data));f:close()
