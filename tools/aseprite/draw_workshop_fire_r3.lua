-- Hand-authored furnace interior cleanup and isolated fire animation review.
-- Existing generated-workshop r2 assets are read-only.
local root=app.params.root or "F:/Documents/楚物志"
local D=dofile(root.."/tools/aseprite/pixel_drawing.lua")
local input=root.."/InheritanceTasks/Art/Pixel/v2/review/generated-workshop/workshop-r2-48.aseprite"
local out=root.."/InheritanceTasks/Art/Pixel/v2/review/workshop-motion-r3"
app.fs.makeAllDirectories(out)
local original=assert(app.open(input));app.activeSprite=original
local original_palette=original.palettes[1]
local palette_colors={}
for i=0,#original_palette-1 do
 local q=original_palette:getColor(i)
 if q.alpha>0 then palette_colors[#palette_colors+1]={q.red,q.green,q.blue} end
end
app.command.ChangePixelFormat{ui=false,format="rgb"}
local source=Image(original);original:close()
local crop=Sprite(90,110,ColorMode.RGB)
crop.cels[1].image=Image(source,Rectangle(322,123,90,110))
app.activeSprite=crop;app.command.SpriteSize{ui=false,width=360,height=440,method="nearest-neighbor"}
crop:saveCopyAs(out.."/furnace-original-4x.png");crop:close()

local ox,oy,w,h=328,132,76,98
local function rgba(r,g,b,a) return app.pixelColor.rgba(r,g,b,a or 255) end
local function near(r,g,b)
 local best,dist=nil,1e20
 for _,p in ipairs(palette_colors) do
  local d=(r-p[1])^2+(g-p[2])^2+(b-p[3])^2
  if d<dist then dist=d;best=p end
 end
 return rgba(best[1],best[2],best[3])
end
local c={
 wall=near(57,35,33),wallshade=near(46,33,34),walllight=near(77,44,38),
 ash=near(74,54,45),ashdark=near(46,35,35),potdark=near(68,46,40),potrim=near(87,59,48),
 red=near(137,52,33),orange=near(211,86,35),gold=near(247,145,47),
 bright=near(232,206,152),core=near(232,206,152),coal=near(102,39,30),coalhot=near(181,66,29),
}
local function blank() return Image(w,h,ColorMode.RGB) end
local function pglobal(im,pts,color)
 local shifted={};for _,p in ipairs(pts) do shifted[#shifted+1]={p[1]-ox,p[2]-oy} end
 D.poly(im,shifted,color)
end
local white=rgba(255,255,255)
local main=blank();local lower=blank();local pot=blank()
-- These masks follow the inner brick boundary, excluding the masonry face.
pglobal(main,{{334,189},{334,157},{336,150},{340,145},{346,140},{353,136},{360,134},{373,134},{382,137},{390,142},{395,149},{398,156},{398,189}},white)
pglobal(lower,{{354,211},{383,211},{383,225},{354,225}},white)
-- Copy the existing pot silhouette separately, rather than repainting the whole vessel.
pglobal(pot,{{343,158},{347,155},{355,152},{361,151},{362,148},{369,148},{370,151},{378,153},{384,155},{387,158}},white)
pglobal(pot,{{345,158},{385,158},{386,165},{385,175},{382,180},{378,183},{355,183},{351,180},{348,175},{346,166}},white)
pglobal(pot,{{342,162},{347,162},{349,165},{347,168},{345,165},{343,165},{344,170},{348,172},{348,175},{344,173},{342,169}},white)
pglobal(pot,{{384,162},{389,161},{392,164},{393,167},{391,171},{386,174},{384,172},{387,170},{390,168},{390,165},{387,164},{385,166}},white)
local function opaque(im,x,y) return app.pixelColor.rgbaA(im:getPixel(x,y))>0 end
local function inside(x,y) return opaque(main,x,y) or opaque(lower,x,y) end
local function clip_interior(im)
 for y=0,h-1 do for x=0,w-1 do if not inside(x,y) then im:drawPixel(x,y,0) end end end
end

-- Only the two interior masks are backfilled. Every exterior source pixel is unchanged.
local patch=blank()
for y=0,h-1 do for x=0,w-1 do
 if inside(x,y) then patch:drawPixel(x,y,c.wall) end
end end
local texture=blank()
pglobal(texture,{{335,151},{344,142},{355,137},{374,136},{386,141},{395,151},{395,161},{389,153},{379,147},{355,146},{342,155},{338,168},{335,176}},c.wallshade)
pglobal(texture,{{340,157},{347,150},{359,148},{370,148},{381,153},{386,161},{383,172},{374,178},{350,177},{340,173}},c.walllight)
D.rect(texture,7,50,63,7,c.ashdark)
D.rect(texture,9,54,58,3,c.ash)
D.rect(texture,26,79,30,14,c.wallshade)
D.rect(texture,28,84,25,10,c.walllight)
D.rect(texture,27,92,29,2,c.ashdark)
-- Lower chamber has deep red soot rather than a rectangular grey inset.
pglobal(texture,{{355,215},{360,213},{375,214},{382,216},{382,224},{355,224}},near(75,33,29))
pglobal(texture,{{357,218},{362,216},{374,216},{381,219},{380,225},{356,225}},near(109,55,48))
clip_interior(texture);patch:drawImage(texture)
-- The undisturbed upper vault is already dark, textured, and contains neither
-- vessel nor fire. Preserve those actual source pixels instead of flattening it.
for y=0,h-1 do for x=0,w-1 do
 if opaque(main,x,y) and oy+y<177 and not opaque(pot,x,y) then
  patch:drawPixel(x,y,source:getPixel(ox+x,oy+y))
 end
 if opaque(lower,x,y) and oy+y<215 then
  patch:drawPixel(x,y,source:getPixel(ox+x,oy+y))
 end
end end
local cleaned=Image(source);cleaned:drawImage(patch,Point(ox,oy))
local clean_source=Sprite(500,300,ColorMode.RGB)
clean_source.layers[1].name="original workshop r2 / untouched outside interior masks"
clean_source.cels[1].image=source
D.layer(clean_source,"opaque local furnace backfill - both baked fires removed",patch,1).position=Point(ox,oy)
clean_source.data="Only chamber interiors changed; original r2 source remains untouched. Vessel is provided as separate foreground."
clean_source:saveAs(out.."/clean-background.aseprite")
clean_source:saveCopyAs(out.."/clean-background.png");clean_source:close()

local surround=blank();local vessel=blank()
for y=0,h-1 do for x=0,w-1 do
 if not inside(x,y) then surround:drawPixel(x,y,source:getPixel(ox+x,oy+y)) end
 if opaque(pot,x,y) then vessel:drawPixel(x,y,source:getPixel(ox+x,oy+y)) end
end end
-- The last pot pixels were mixed with baked flame in r2. Close only the base
-- with restrained brown metal, instead of copying orange flame into foreground.
local base_repair=blank()
pglobal(base_repair,{{350,178},{354,180},{360,181},{373,181},{381,178},{380,182},{376,184},{356,184},{352,182}},c.potdark)
pglobal(base_repair,{{352,180},{357,182},{374,182},{379,180},{377,183},{355,183}},c.potrim)
for y=0,h-1 do for x=0,w-1 do
 if not opaque(pot,x,y) and app.pixelColor.rgbaA(base_repair:getPixel(x,y))>0 then
  base_repair:drawPixel(x,y,0)
 end
end end
vessel:drawImage(base_repair)
local foreground=blank();foreground:drawImage(surround);foreground:drawImage(vessel)
local fg=Sprite(w,h,ColorMode.RGB);fg:deleteLayer(fg.layers[1])
D.layer(fg,"fixed masonry and front lip / source pixels",surround)
D.layer(fg,"original medicine vessel silhouette",vessel)
D.anchor(fg,"stage_origin",0,0)
fg.data="Place at (328,132), native size. Masonry and pot never move. Vessel's fire-contaminated base is repaired."
fg:saveAs(out.."/furnace-foreground.aseprite");fg:saveCopyAs(out.."/furnace-foreground.png");fg:close()
pot:saveAs(out.."/pot-mask.png");main:saveAs(out.."/main-interior-mask.png");lower:saveAs(out.."/lower-interior-mask.png")

local motion=Sprite(w,h,ColorMode.RGB);motion:deleteLayer(motion.layers[1])
for k=2,36 do motion:newEmptyFrame(k) end
for _,fr in ipairs(motion.frames) do fr.duration=.10 end
local fire_atlas=Image(w*12,h*3,ColorMode.RGB)
local smoke_atlas=Image(w*12,h*3,ColorMode.RGB)
local glow_atlas=Image(w*12,h*3,ColorMode.RGB)
-- Hand-posed 12-step offsets. Opposite tongues are deliberately out of phase.
local phases={0,3,6,9,2}
local sway={-1,0,1,2,1,0,-1,-2,-1,0,1,0}
local rise={0,2,4,3,1,-1,-2,-1,1,2,1,0}
local smoke_alpha={0,20,32,44,48,44,36,28,20,12,4,0}
local levels={.35,1.0,1.45}
local names={"low","medium","high"}
local samples={}
local fire_frames={}
for level=1,3 do
 for f=1,12 do
  local k=(level-1)*12+f
  local bed,outer,inner,smoke,glow=blank(),blank(),blank(),blank(),blank()
  -- A low, connected ember bed supports the vessel; large quiet coal clusters
  -- stay put while only their fissures warm. No row of identical glowing blobs.
  D.poly(bed,{{8,55},{12,53},{18,54},{24,52},{31,53},{39,53},{44,52},{49,54},{58,53},{65,54},{68,56},{66,58},{9,58}},c.ashdark)
  for i,spec in ipairs({{11,54,7},{23,54,8},{36,55,9},{48,54,6},{58,55,8}}) do
   local x,y,len=spec[1],spec[2],spec[3]
   local pulse=(f+phases[i])%12
   D.poly(bed,{{x-2,y},{x,y-2},{x+len-2,y-1},{x+len,y+1},{x+len-1,y+2},{x-2,y+2}},c.coal)
   D.line(bed,x,y,x+len-3,y,(pulse<3 and level>1) and c.orange or c.red)
   if level==3 and pulse<3 then D.line(bed,x+2,y,x+4,y,c.gold) end
  end
  -- Small curls spread asymmetrically around the pot base. Roots remain fixed;
  -- neck/tip positions change by at most two native pixels between poses.
  local tongue_specs
  if level==1 then tongue_specs={{15,56,5,4,0},{36,56,3,9,6},{63,56,4,3,3}}
  elseif level==2 then tongue_specs={{14,56,16,6,0},{36,56,10,12,6},{64,56,12,5,3}}
  else tongue_specs={{14,56,23,6,0},{36,56,15,13,6},{64,56,20,5,3}} end
  -- Dark orange joins the roots while the upper curls keep open gaps.
  D.poly(outer,{{9,56},{15,54},{23,55},{28,54},{39,55},{45,54},{54,56},{63,54},{68,56},{67,57},{9,57}},c.red)
  for i,t in ipairs(tongue_specs) do
   local cx,y,base_ht,width,phase=t[1],t[2],t[3],t[4],t[5]
   local index=(f+phase-1)%12+1
   local bend=sway[index];local ht=base_ht+math.floor(rise[index]*(level==1 and .25 or .75))
   local top=y-ht;local neck=cx+bend;local dir=i==3 and -1 or 1
   -- Concave shoulder, side fork and hooked head are individually spaced.
   -- The centre bloom is wider/lower and half a cycle behind the left curl.
   local pts={{-width,0},{-width-1,-2},{-width+1,-math.floor(ht*.30)},
    {-3,-math.floor(ht*.43)},{-4,-math.floor(ht*.68)},{-1,-math.floor(ht*.54)},
    {bend-1,-ht+3},{bend-3,-ht},{bend+1,-ht+1},{bend+3,-ht+4},
    {2,-math.floor(ht*.43)},{width-1,-math.floor(ht*.29)},{width,-2},{width,0}}
   local actual={};for _,q in ipairs(pts) do actual[#actual+1]={cx+q[1]*dir,y+q[2]} end
   D.poly(outer,actual,c.orange)
   local pts2={{-width+2,0},{-3,-2},{-2,-math.floor(ht*.32)},
    {bend,-math.floor(ht*.64)},{bend+1,-math.floor(ht*.58)},
    {1,-math.floor(ht*.25)},{width-2,-1},{width-1,0}}
   actual={};for _,q in ipairs(pts2) do actual[#actual+1]={cx+q[1]*dir,y+q[2]} end
   D.poly(inner,actual,c.gold)
   if level>1 then
    D.poly(inner,{{cx-2,y},{cx-1,y-2},{cx,y-math.floor(ht*.22)},{cx+1,y-2},{cx+3,y}},c.bright)
   end
  end
  -- Under-pot heat is a broken yellow thread, not a solid horizontal orange bar.
  if level>1 then
   D.line(inner,29,54,34,54,c.gold);D.line(inner,36,55,42,55,c.bright)
   if level==3 then D.line(inner,29,53,34,53,c.bright) end
  end
  -- Lower opening: an irregular ember bed, with only two differently sized
  -- flickers. Most of the stoke hole remains dark so it reads as a deep cavity.
  D.poly(bed,{{28,91},{31,89},{37,91},{41,90},{46,91},{51,89},{55,91},{55,94},{28,94}},c.coal)
  D.line(bed,31,92,36,92,c.red);D.line(bed,41,92,46,92,c.coalhot);D.line(bed,49,91,52,92,c.red)
  for i,t in ipairs({{37,93,4,0},{49,93,3,7}}) do
   local cx,y,base_ht,phase=t[1],t[2],t[3],t[4]
   local index=(f+phase-1)%12+1
   local ht=math.max(1,math.floor(base_ht*levels[level]+rise[index]*.3))
   local bend=sway[index]
   if level>1 or index<6 then
    D.poly(outer,{{cx-3,y},{cx-2,y-2},{cx+bend,y-ht},{cx+bend+1,y-ht+2},{cx+2,y-1},{cx+3,y}},c.orange)
    D.line(inner,cx-1,y,cx+1,y,level==1 and c.gold or c.bright)
    if level==3 then D.line(inner,cx,y-2,cx,y,c.gold) end
   end
  end
  clip_interior(bed);clip_interior(outer);clip_interior(inner)
  -- Grey soot remains inside the chamber and behind the vessel. Two puffs
  -- alternate gently; their alpha fades before the loop wraps.
  for n=0,1 do
   local q=(f+n*6-1)%12+1
   local a=math.floor(smoke_alpha[q]*(level==1 and 1.1 or level==2 and .8 or .6))
   local x=n==0 and 11 or 62;local y=43-math.floor((q-1)*1.1)
   local col=rgba(127,111,107,a)
   D.poly(smoke,{{x,y},{x-2,y-3},{x-1,y-6},{x+1,y-8},{x,y-11},{x+2,y-10},{x+3,y-7},{x+1,y-4},{x+2,y-1}},col)
  end
  clip_interior(smoke)
  -- Warm reflection is its own transparent asset, drawn AFTER foreground.
  local alpha=({5,16,30})[level]+math.max(0,rise[f])
  local light=rgba(255,153,61,alpha)
  D.poly(glow,{{3,24},{6,20},{8,23},{8,54},{11,59},{7,60},{3,54}},light)
  D.poly(glow,{{69,22},{73,26},{73,54},{69,59},{66,59},{69,52}},light)
  D.poly(glow,{{23,79},{57,79},{58,81},{55,82},{26,82},{26,94},{23,94}},light)
  D.poly(glow,{{21,47},{27,49},{43,49},{51,47},{49,50},{42,52},{27,52},{22,50}},rgba(255,167,72,math.floor(alpha*.65)))
  D.layer(motion,"fixed coal shapes and changing ember surfaces",bed,k)
  D.layer(motion,"independent flame tongues",outer,k)
  D.layer(motion,"gold and pale flame cores",inner,k)
  D.layer(motion,"soot puffs / separate semi-transparent output",smoke,k)
  D.layer(motion,"warm reflections / overlay after static foreground",glow,k)
  local fire=blank();fire:drawImage(bed);fire:drawImage(outer);fire:drawImage(inner)
  fire_atlas:drawImage(fire,Point((f-1)*w,(level-1)*h))
  smoke_atlas:drawImage(smoke,Point((f-1)*w,(level-1)*h))
  glow_atlas:drawImage(glow,Point((f-1)*w,(level-1)*h))
  fire_frames[k]={fire=fire,smoke=smoke,glow=glow}
  if f==5 then
   local composed=Image(cleaned)
   composed:drawImage(fire,Point(ox,oy));composed:drawImage(smoke,Point(ox,oy))
   composed:drawImage(foreground,Point(ox,oy));composed:drawImage(glow,Point(ox,oy))
   composed:saveAs(out.."/workshop-"..names[level].."-sample.png")
   local detail=Image(composed,Rectangle(322,123,90,110))
   local ds=Sprite(90,110,ColorMode.RGB);ds.cels[1].image=detail;app.activeSprite=ds
   app.command.SpriteSize{ui=false,width=360,height=440,method="nearest-neighbor"}
   ds:saveCopyAs(out.."/furnace-"..names[level].."-sample-4x.png");ds:close()
  end
 end
 local tag=motion:newTag((level-1)*12+1,level*12);tag.name=names[level];tag.data="12-frame loop; retain frame index when intensity changes"
end
D.anchor(motion,"main_fire_base",37,55);D.anchor(motion,"lower_fire_base",41,92)
motion.data="Native origin (328,132). 3 intensity loops, each 12 x 100 ms. Render fire, smoke, static foreground, then glow. No whole-furnace transforms."
motion:saveAs(out.."/furnace-motion.aseprite");motion:close()
fire_atlas:saveAs(out.."/fire-atlas.png")
smoke_atlas:saveAs(out.."/smoke-atlas.png")
glow_atlas:saveAs(out.."/warm-glow-atlas.png")

-- Local inspection animation only; no full-scene per-frame atlas is generated.
local contact=Image(90*4,110*3,ColorMode.RGB)
local preview=Sprite(90,110,ColorMode.RGB);preview:deleteLayer(preview.layers[1])
for f=2,12 do preview:newEmptyFrame(f) end
for _,fr in ipairs(preview.frames) do fr.duration=.10 end
for f=1,12 do
 local n=12+f;local q=fire_frames[n]
 local composed=Image(cleaned);composed:drawImage(q.fire,Point(ox,oy));composed:drawImage(q.smoke,Point(ox,oy))
 composed:drawImage(foreground,Point(ox,oy));composed:drawImage(q.glow,Point(ox,oy))
 local view=Image(composed,Rectangle(322,123,90,110))
 D.layer(preview,"local normal-fire review; masonry fixed",view,f)
 contact:drawImage(view,Point(((f-1)%4)*90,math.floor((f-1)/4)*110))
end
local cs=Sprite(360,330,ColorMode.RGB);cs.cels[1].image=contact;app.activeSprite=cs
app.command.SpriteSize{ui=false,width=720,height=660,method="nearest-neighbor"}
cs:saveCopyAs(out.."/furnace-medium-all-frames-2x.png");cs:close()
preview:newTag(1,12).name="normal_fire_loop"
preview:saveAs(out.."/furnace-local-preview.aseprite")
app.activeSprite=preview;app.command.SpriteSize{ui=false,width=360,height=440,method="nearest-neighbor"}
preview:saveCopyAs(out.."/furnace-local-preview-4x.gif");preview:close()
local report={
 status="review only; not gameplay or user acceptance",source=input,
 stage_size={500,300},origin={ox,oy},frame_size={w,h},atlas_columns=12,atlas_rows=3,
 rows=names,frame_duration_ms=100,loop_duration_ms=1200,
 render_order={"clean-background.png @ 0,0","fire-atlas.png @ 328,132","smoke-atlas.png @ 328,132","furnace-foreground.png @ 328,132","warm-glow-atlas.png @ 328,132"},
 anchors={main_fire_base={365,187},lower_fire_base={369,224}},
 response={send_air_delay_ms=140,attack_ms=280,release_ms=550,keep_frame_phase=true,never_extinguish_on_key_release=true},
 cleanup={changed_only="main-interior-mask plus lower-interior-mask",vessel_base="last 3-5 pot pixels reconstructed because original flame was baked across its edge"},
 retained_background={"entire room","outer furnace masonry and chimney","shelves and pottery","baked general ambient and brick lighting"},
 limitations={"r2 masonry's baked warm rim remains static; new glow provides mild additional response","smoke is stylized soot inside chamber, not an authenticated process depiction","normal-speed visual review still required in combined character and bellows scene"}
}
local f=assert(io.open(out.."/fire-anchors-and-layers.json","w"));f:write(json.encode(report));f:close()
