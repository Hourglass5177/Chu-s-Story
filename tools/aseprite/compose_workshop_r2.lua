-- Editable art review: revised generated workshop + hand-authored travel
-- blogger in work clothes, with independently moving hands and bellows.
-- This does not replace the current game's accepted physics or score.
local root=app.params.root or "F:/Documents/楚物志"
local D=dofile(root.."/tools/aseprite/pixel_drawing.lua")
local review=root.."/InheritanceTasks/Art/Pixel/v2/review"
local out=review.."/workshop-composition-r2"
app.fs.makeAllDirectories(out)
local actor_source=assert(app.open(review.."/avatar-identity-r2/travel-redraw.aseprite"))
local actor=Sprite(120,164,ColorMode.INDEXED)
actor:setPalette(actor_source.palettes[1]);actor.transparentColor=0
actor:deleteLayer(actor.layers[1]);actor.gridBounds=Rectangle(0,0,1,1)
for i=2,8 do actor:newEmptyFrame(i) end
for _,fr in ipairs(actor.frames) do fr.duration=.10 end
local hands={0,2,5,8,10,8,5,2}
local function img() return Image(120,164,ColorMode.INDEXED) end
local function poly(im,a,c) D.poly(im,a,c) end
local function line(im,x,y,a,b,c,w) D.line(im,x,y,a,b,c,w) end
local function rect(im,x,y,w,h,c) D.rect(im,x,y,w,h,c) end
local function cel(name,im,k)
  local l=nil;for _,x in ipairs(actor.layers) do if x.name==name then l=x end end
  if not l then l=actor:newLayer();l.name=name end
  actor:newCel(l,k,im,Point(0,0))
end
local shadow=img();D.ellipse(shadow,19,153,63,7,19)
for k=1,8 do cel("ground contact shadow",shadow,k) end
local body=img()
-- Feet are fixed; only arms and piston change in this review action.
poly(body,{{33,126},{47,126},{46,151},{50,154},{48,158},{29,158},{28,155},{33,151}},1)
poly(body,{{51,126},{64,126},{66,150},{73,153},{74,157},{51,157},{50,152}},1)
poly(body,{{35,128},{45,128},{43,151},{33,152}},20)
poly(body,{{53,128},{63,128},{64,151},{53,151}},17)
poly(body,{{31,153},{44,152},{47,155},{31,156}},2)
poly(body,{{53,153},{65,152},{71,155},{53,155}},2)
line(body,33,155,44,155,18);line(body,55,155,67,155,18)
-- Rolled yellow work shirt over a practical indigo apron.
poly(body,{{37,65},{55,65},{66,72},{71,93},{68,111},{66,131},{52,134},{34,131},{29,111},{27,88},{29,74}},1)
poly(body,{{38,67},{54,67},{64,73},{68,93},{65,111},{63,129},{51,131},{36,128},{32,110},{30,88},{32,75}},13)
poly(body,{{56,72},{63,75},{65,88},{63,101},{59,98}},14)
poly(body,{{32,76},{37,73},{38,90},{34,97},{31,90}},15)
poly(body,{{38,80},{57,80},{63,103},{64,129},{50,132},{35,128},{34,108}},16)
poly(body,{{39,82},{55,82},{60,103},{61,126},{49,129},{37,126},{37,108}},17)
poly(body,{{38,102},{48,103},{57,101},{59,111},{55,118},{43,119},{38,114}},20)
line(body,39,103,56,103,18);line(body,40,105,40,114,18)
line(body,38,71,40,84,16,2);line(body,56,72,54,83,16,2)
rect(body,32,99,32,3,19);rect(body,56,99,7,2,18)
poly(body,{{35,64},{55,64},{59,69},{54,73},{46,75},{35,72},{32,68}},1)
poly(body,{{35,65},{54,65},{57,69},{52,71},{45,73},{36,70},{34,68}},17)
line(body,38,67,48,69,18)
for k=1,8 do cel("rolled work shirt and indigo apron",body,k) end
-- Keep original identity features as separate editable layers, at native size.
for _,name in ipairs({
  "loose low twin tails - original ash rose hair",
  "face - original cheek and jaw contour",
  "hair - separated swept bangs and curled side locks",
  "yellow bucket hat - grouped shading, no stipple",
  "anime eyes - original lash curve, irises and highlights"}) do
  for _,l in ipairs(actor_source.layers) do if l.name==name then
    local src=l:cel(1)
    local im=img();im:drawImage(src.image,Point(src.position.x+10,src.position.y))
    for k=1,8 do cel(name,im,k) end
  end end
end
actor_source:close()
local palm_positions={}
for k,pull in ipairs(hands) do
  local im=img()
  local handx=78-pull
  local handy=105
  -- Far arm has its own elbow, visible under the nearer forearm.
  poly(im,{{30,77},{37,77},{44,91},{53,99},{handx-4,101},{handx-1,107},{handx-7,110},{49,107},{38,99},{29,86}},1)
  poly(im,{{31,78},{36,79},{43,93},{53,101},{handx-5,103},{handx-3,106},{handx-7,108},{50,105},{39,97},{31,85}},13)
  poly(im,{{44,93},{51,98},{52,104},{46,102},{41,98}},15)
  poly(im,{{52,100},{handx-5,102},{handx-2,104},{handx-3,107},{handx-7,108},{52,104}},6)
  line(im,56,104,handx-6,106,7)
  -- Near shoulder/cuff/elbow remain connected while forearm tracks grip.
  poly(im,{{60,75},{65,76},{71,85},{71,91},{75,96},{handx+3,100},{handx+5,104},{handx+3,110},{handx-1,111},{70,104},{63,99},{61,91},{59,86}},1)
  poly(im,{{61,77},{64,78},{69,85},{69,91},{73,98},{handx+2,102},{handx+3,105},{handx+1,109},{70,102},{65,97},{63,90},{61,85}},13)
  poly(im,{{65,88},{70,89},{72,95},{68,98},{65,94}},15)
  poly(im,{{71,96},{handx+2,101},{handx+3,104},{handx+1,107},{70,101},{68,98}},6)
  line(im,72,100,handx,104,7)
  -- Thumb wrapped over the horizontal grip, finger curve at the underside.
  poly(im,{{handx-2,100},{handx+2,100},{handx+5,102},{handx+5,107},{handx+2,109},{handx-1,108},{handx-3,104}},1)
  poly(im,{{handx-1,101},{handx+2,101},{handx+4,103},{handx+4,106},{handx+2,108},{handx,107},{handx-2,104}},6)
  line(im,handx+1,104,handx+4,104,7);line(im,handx+1,106,handx+3,106,7)
  cel("bent arms and hands / contact frame "..k,im,k)
  palm_positions[#palm_positions+1]={frame=k,x=handx+2,y=105,pull=pull}
end
local tag=actor:newTag(1,8);tag.name="pump_contact_review"
local sl=actor:newSlice(Rectangle(0,0,120,164));sl.name="feet";sl.pivot=Point(49,158)
actor.data="Travel blogger identity retained. Separate work outfit and native-pixel hands. Review only; not accepted game atlas."
actor:saveAs(out.."/travel-work-action.aseprite")
actor:saveCopyAs(out.."/travel-work-keyframe.png")

-- Bellows is one independent source, with stationary body and moving piston.
local bp=Palette(12)
local hex={"292c35","5f413a","84533d","a8754c","c99962","e5bd82","3e424b","666971","92918c","402f30","6c4c3e"}
bp:setColor(0,Color{r=0,g=0,b=0,a=0})
for i,h in ipairs(hex) do bp:setColor(i,Color{r=tonumber(h:sub(1,2),16),g=tonumber(h:sub(3,4),16),b=tonumber(h:sub(5,6),16),a=255}) end
local b=Sprite(136,75,ColorMode.INDEXED);b:setPalette(bp);b.transparentColor=0;b:deleteLayer(b.layers[1])
for i=2,8 do b:newEmptyFrame(i) end
for _,fr in ipairs(b.frames) do fr.duration=.1 end
local base=Image(136,75,ColorMode.INDEXED)
-- Pipe, support, front and side planes are drawn as coherent wood/metal forms.
D.poly(base,{{111,27},{132,29},{134,33},{132,38},{110,35}},1)
D.poly(base,{{111,29},{130,31},{131,35},{111,33}},7)
D.line(base,114,30,129,32,8)
D.poly(base,{{48,48},{56,48},{54,71},{45,71}},1)
D.poly(base,{{50,50},{54,50},{52,69},{48,69}},3)
D.poly(base,{{102,48},{111,46},{115,68},{107,71}},1)
D.poly(base,{{104,50},{110,49},{112,67},{109,69}},3)
D.poly(base,{{42,47},{111,43},{116,49},{110,57},{42,59},{39,55}},1)
D.poly(base,{{43,49},{109,46},{112,49},{108,54},{43,56},{41,54}},4)
D.line(base,44,56,108,54,2)
D.poly(base,{{42,15},{92,9},{116,22},{116,46},{91,53},{42,43}},1)
D.poly(base,{{45,17},{91,12},{111,23},{91,30},{45,26}},5)
D.poly(base,{{45,28},{91,33},{91,50},{45,41}},3)
D.poly(base,{{93,32},{113,24},{113,44},{93,49}},2)
D.line(base,47,19,88,15,6);D.line(base,49,24,87,28,4)
D.line(base,57,17,98,26,3);D.line(base,75,14,105,24,3)
D.line(base,46,35,89,43,2);D.line(base,47,37,87,45,4)
D.line(base,95,36,111,29,3);D.line(base,95,43,111,37,3)
-- Iron hoops are restrained, not randomly scattered rivets.
for _,x in ipairs({48,84}) do
  D.poly(base,{{x,17},{x+3,17},{x+3,27},{x+4,43},{x+1,43},{x,27}},7)
  D.line(base,x+1,18,x+2,26,9)
  D.rect(base,x+1,31,1,1,9);D.rect(base,x+2,39,1,1,9)
end
local bl=b:newLayer();bl.name="stationary box, stool and air pipe"
for k=1,8 do b:newCel(bl,k,base,Point(0,0)) end
bl=b:newLayer();bl.name="piston and grip / exact hand contact"
for k,pull in ipairs(hands) do
  local im=Image(136,75,ColorMode.INDEXED)
  local grip=20-pull
  D.poly(im,{{grip,25},{44,25},{44,30},{grip,30}},1)
  D.rect(im,grip+2,26,42-grip,3,4);D.line(im,grip+2,26,42,26,6)
  D.poly(im,{{grip-3,22},{grip+4,22},{grip+5,24},{grip+5,31},{grip+3,33},{grip-3,33},{grip-4,31},{grip-4,24}},1)
  D.rect(im,grip-2,23,5,9,3);D.line(im,grip-1,24,grip-1,30,5)
  b:newCel(bl,k,im,Point(0,0))
end
local bt=b:newTag(1,8);bt.name="pump_contact_review"
b.data="Illustrative wooden medicine-workshop bellows, not an authenticated Xia equipment reconstruction."
b:saveAs(out.."/bellows-action.aseprite")

-- Composite in RGB preserves each source palette. Output is a review scene,
-- not a falsely indexed atlas with other sprites' color indices reinterpreted.
local bg=assert(app.open(review.."/generated-workshop/workshop-r2-48.aseprite"))
app.activeSprite=bg;app.command.ChangePixelFormat{ui=false,format="rgb"}
local bgim=Image(bg);bg:close()
app.activeSprite=actor;app.command.ChangePixelFormat{ui=false,format="rgb"}
app.activeSprite=b;app.command.ChangePixelFormat{ui=false,format="rgb"}
local scene=Sprite(500,300,ColorMode.RGB);scene:deleteLayer(scene.layers[1])
for i=2,8 do scene:newEmptyFrame(i) end
for _,fr in ipairs(scene.frames) do fr.duration=.1 end
local back=scene:newLayer();back.name="generated medicinal workshop r2 / native palette cleanup"
local prop=scene:newLayer();prop.name="independent wooden bellows"
local person=scene:newLayer();person.name="travel blogger work pose / original identity"
-- The shared grip is global (197 - pull, 184); actor and prop data agree.
for k=1,8 do
  scene:newCel(back,k,bgim,Point(0,0))
  app.activeSprite=b;app.activeFrame=b.frames[k]
  local im=Image(136,75,ColorMode.RGB);im:drawSprite(b,k)
  scene:newCel(prop,k,im,Point(175,157))
  app.activeSprite=actor;app.activeFrame=actor.frames[k]
  im=Image(120,164,ColorMode.RGB);im:drawSprite(actor,k)
  scene:newCel(person,k,im,Point(117,79))
end
scene:newTag(1,8).name="pump_contact_review"
scene:saveAs(out.."/workshop-travel-review.aseprite")
scene:saveCopyAs(out.."/workshop-travel-review.png")
local preview=Sprite(scene);app.activeSprite=preview
app.command.SpriteSize{ui=false,width=1000,height=600,method="nearest-neighbor"}
preview:saveCopyAs(out.."/workshop-travel-review-2x.png")
preview:close();scene:close();actor:close();b:close()
local f=assert(io.open(out.."/contact-anchors.json","w"))
f:write(json.encode({status="art-review; not gameplay acceptance",actor_origin={117,79},bellows_origin={175,157},frames=palm_positions}));f:close()
