-- Chu P1: every contour below is authored on the native one-pixel grid.
-- Run with Aseprite --batch --script-param root=<workspace> --script this.lua.
local root=app.params.root or "F:/Documents/楚物志"
local D=dofile(root.."/tools/aseprite/pixel_drawing.lua")
local R,L,P,E,O=D.rect,D.line,D.poly,D.ellipse,D.round
local function image(w,h) return D.img(w,h) end

local function ui()
  local s=D.sprite(576,348)
  local im=image(576,348)
  O(im,0,0,576,348,"deepwood",9);O(im,2,2,572,344,"woodshadow",8)
  O(im,4,3,568,338,"wood",7);O(im,6,5,564,332,"woodlight",6)
  R(im,10,7,554,2,"goldwood");R(im,8,334,557,3,"woodshadow")
  -- Broad restrained grain clusters run along the cabinet rather than noise.
  L(im,24,12,159,12,"goldwood");L(im,176,12,243,12,"goldwood")
  L(im,298,11,456,11,"wood");L(im,26,331,145,331,"wood")
  L(im,166,333,290,333,"goldwood");L(im,360,331,492,331,"wood")
  O(im,8,20,508,308,"deepwood",5);O(im,10,22,504,304,"ink",3)
  R(im,12,24,500,300,0)
  O(im,520,20,48,308,"woodshadow",5);O(im,521,20,46,304,"cream",4)
  R(im,524,25,39,1,"offwhite")
  -- One volume knob and a cloth speaker, with broad woven bands.
  E(im,529,40,31,33,"woodshadow");E(im,529,39,31,30,"brassdark")
  E(im,532,40,25,25,"honey");E(im,534,41,20,20,"cream")
  R(im,544,44,2,8,"woodshadow");L(im,535,71,554,71,"goldwood")
  O(im,529,239,31,72,"woodshadow",3);R(im,532,243,25,63,"brassdark")
  for y=244,304,4 do R(im,533,y,23,2,"woodlight") end
  for x=534,556,5 do R(im,x,244,1,61,"woodshadow") end
  -- Feet are part of the cabinet, not a floating drop shadow.
  R(im,24,344,38,4,"deepwood");R(im,516,344,36,4,"deepwood")
  D.layer(s,"wood cabinet / transparent screen",im)
  D.anchor(s,"screen_origin",12,24);D.save(s,"ui/tv",true)
  local styles={panel={"woodshadow","cream","paper"},button={"deepwood","goldwood","cream"},
    button_hover={"woodshadow","honey","paper"},button_pressed={"deepwood","wood","goldwood"},
    button_focus={"teal","honey","paper"},button_disabled={"brassdark","stone_light","stone_hi"}}
  for name,cs in pairs(styles) do
    s=D.sprite(32,32);im=image(32,32)
    O(im,0,0,32,32,cs[1],4);O(im,2,2,28,27,cs[2],3);O(im,3,3,26,23,cs[3],2)
    R(im,5,4,22,1,name=="button_disabled" and "silver" or "offwhite")
    R(im,5,27,22,2,cs[2]);D.layer(s,"panel / 6px corners",im)
    D.save(s,"ui/"..name,true)
  end
  for _,name in ipairs({"checkbox_off","checkbox_on"}) do
    s=D.sprite(16,16);im=image(16,16)
    O(im,0,0,16,16,"woodshadow",3);O(im,2,2,12,12,"cream",2)
    R(im,3,3,10,1,"honey")
    if name=="checkbox_on" then L(im,3,8,6,11,"leafshade",2);L(im,6,11,12,4,"leafshade",2) end
    D.layer(s,"binary setting",im);D.save(s,"ui/"..name,true)
  end
  s=D.sprite(12,16);im=image(12,16)
  O(im,0,0,12,16,"woodshadow",3);O(im,2,1,8,12,"honey",2)
  R(im,3,2,6,2,"paper");R(im,5,5,2,6,"woodlight")
  D.layer(s,"volume thumb",im);D.save(s,"ui/slider_grip",true)
  s=D.sprite(16,8);im=image(16,8)
  O(im,0,1,16,6,"woodshadow",2);R(im,2,2,12,2,"deepwood");R(im,2,5,12,1,"honey")
  D.layer(s,"volume rail",im);D.save(s,"ui/slider_track",true)
  s=D.sprite(48,224);im=image(48,224)
  O(im,2,0,44,224,"deepwood",4);O(im,4,2,40,218,"goldwood",3)
  R(im,8,10,32,204,"cream");R(im,13,15,18,191,"woodshadow")
  R(im,15,17,14,187,"deepwood")
  for y=21,201,18 do R(im,33,y,6,1,"woodshadow") end
  D.layer(s,"thermometer shell",im);D.save(s,"alchemy/heat_gauge",true)
  s=D.sprite(340,24);im=image(340,24)
  O(im,0,0,340,24,"deepwood",4);O(im,2,2,336,20,"goldwood",3)
  O(im,5,5,330,14,"woodshadow",2);R(im,7,7,326,10,"deepwood")
  D.layer(s,"brew progress shell",im);D.save(s,"alchemy/brew_gauge",true)
end

local function jar(im,x,y,w,h,body)
  O(im,x,y+3,w,h-3,"woodshadow",4);O(im,x+2,y+5,w-4,h-7,body,3)
  R(im,x+3,y,w-6,4,"woodshadow");R(im,x+4,y,w-8,2,"honey")
  R(im,x+5,y+9,3,h-16,"cream")
end
local function workshop()
  local s=D.sprite(500,300);local im=image(500,300)
  R(im,0,0,500,300,"cream");R(im,0,22,500,168,"honey")
  R(im,0,26,500,154,"cream");R(im,0,180,500,8,"goldwood")
  R(im,0,188,500,112,"woodlight")
  R(im,0,0,500,13,"woodshadow");R(im,0,13,500,5,"wood")
  for _,x in ipairs({0,268,486}) do R(im,x,18,12,171,"wood");R(im,x+2,18,3,167,"woodlight") end
  -- Floor boards: large uninterrupted surfaces with a few knots.
  for y=207,300,28 do R(im,0,y,500,2,"wood");R(im,0,y+2,500,1,"goldwood") end
  for _,b in ipairs({{48,190,16},{212,210,24},{359,238,24},{91,266,25},{443,270,29}}) do R(im,b[1],b[2],2,b[3],"wood") end
  L(im,28,246,57,246,"wood");L(im,29,249,51,249,"goldwood")
  L(im,307,281,342,281,"wood");L(im,313,284,336,284,"goldwood")
  D.layer(s,"wall beams and floorboards",im)
  im=image(500,300)
  O(im,24,36,124,113,"woodshadow",3);R(im,29,41,114,100,"sky")
  P(im,{{29,98},{52,77},{73,85},{106,57},{143,91},{143,139},{29,139}},"lightblue")
  P(im,{{29,123},{65,98},{91,117},{123,99},{143,112},{143,139},{29,139}},"leaflit")
  R(im,30,43,2,93,"offwhite");R(im,83,41,5,103,"wood")
  R(im,29,88,114,5,"wood");R(im,30,89,112,1,"goldwood")
  R(im,23,145,128,7,"woodshadow");R(im,21,142,132,5,"goldwood")
  R(im,22,142,130,1,"cream")
  -- Sun patch is deliberately quiet, without dither or random flecks.
  P(im,{{29,154},{143,154},{186,186},{58,186}},"paper")
  D.layer(s,"window and quiet daylight",im)
  im=image(500,300)
  O(im,172,43,78,132,"woodshadow",2);R(im,176,47,70,122,"wood")
  R(im,178,48,66,27,"deepwood");R(im,178,77,66,4,"goldwood")
  jar(im,183,50,16,25,"teal");jar(im,207,54,13,21,"honey");jar(im,226,51,13,24,"coral")
  for row=0,3 do for col=0,2 do
    local x,y=179+col*22,85+row*19
    R(im,x,y,20,17,"woodshadow");R(im,x+1,y+1,18,14,"woodlight")
    R(im,x+2,y+2,16,1,"goldwood");R(im,x+5,y+6,10,4,"cream");R(im,x+8,y+12,4,2,"deepwood")
  end end
  R(im,173,175,5,8,"woodshadow");R(im,242,175,5,8,"woodshadow")
  -- Two hanging herbs, built as clustered leaves, not one-pixel confetti.
  for _,x in ipairs({302,336}) do
    L(im,x,24,x,58,"woodshadow");L(im,x-5,45,x+5,61,"leafshade",2)
    for k=0,3 do E(im,x-7+k%2*8,47+k*5,9,5,k%2==0 and "leaf" or "leafshade") end
    R(im,x-2,44,5,3,"honey")
  end
  -- Far shelf and ceramic vessel remain subordinate to the furnace.
  R(im,371,84,99,5,"woodshadow");R(im,369,81,103,3,"goldwood")
  jar(im,381,49,24,32,"teal");jar(im,426,60,16,21,"honey")
  D.layer(s,"medicine cabinet shelf and herbs",im)
  D.save(s,"alchemy/background",true)

  s=D.sprite(150,184);im=image(150,184)
  E(im,10,168,130,14,"woodshadow")
  -- Broad fired-brick base and dark arch; opening is transparent for fire.
  O(im,20,89,110,79,"woodshadow",5);R(im,22,92,106,72,"brick")
  for row=0,3 do
    R(im,23,99+row*17,104,2,"woodshadow")
    for col=0,3 do R(im,24+col*29+(row%2)*13,92+row*17,2,8,"woodshadow") end
  end
  R(im,17,162,118,9,"woodshadow");R(im,16,159,120,5,"wood")
  O(im,45,112,61,50,"deepwood",16);O(im,49,116,53,43,0,13)
  R(im,52,153,47,6,"deepwood")
  R(im,54,153,39,3,"woodshadow")
  -- Rounded bronze vessel: clustered warm highlight, no gradients.
  P(im,{{30,67},{38,40},{48,33},{103,33},{116,45},{123,72},{118,93},{106,106},{43,106},{29,93}},"deepwood")
  P(im,{{33,67},{42,43},{53,37},{101,37},{112,48},{118,72},{113,90},{103,101},{44,101},{34,90}},"brassdark")
  P(im,{{38,60},{47,43},{97,40},{108,49},{112,75},{105,92},{48,92},{39,80}},"woodlight")
  P(im,{{44,59},{49,46},{66,43},{64,90},{51,87},{44,75}},"goldwood")
  L(im,50,48,59,46,"honey",2);R(im,40,92,68,4,"woodshadow")
  E(im,34,29,87,18,"deepwood");E(im,37,28,81,14,"goldwood")
  E(im,42,26,70,11,"honey");R(im,69,16,17,11,"woodshadow")
  O(im,67,13,21,8,"brassdark",3);R(im,70,14,14,2,"goldwood")
  -- Side handles and inlet form the real contact target of the bellows.
  O(im,16,57,20,26,"deepwood",6);O(im,19,60,13,20,"woodlight",4);R(im,24,63,10,13,0)
  O(im,117,57,17,26,"deepwood",6);O(im,120,60,10,20,"woodlight",4);R(im,116,63,10,13,0)
  R(im,0,135,23,10,"deepwood");R(im,0,136,25,5,"brassdark");R(im,1,136,23,2,"goldwood")
  D.layer(s,"bronze vessel brick furnace",im);D.anchor(s,"fire_opening",75,139)
  D.save(s,"alchemy/furnace",true)

  s=D.sprite(92,70);D.frames(s,8,.1)
  local pulls={0,2,5,8,10,8,5,2}
  for frame,dx in ipairs(pulls) do
    im=image(92,70)
    R(im,17,43,61,5,"deepwood");R(im,22,47,5,20,"woodshadow");R(im,69,47,5,20,"woodshadow")
    R(im,24,48,2,17,"woodlight");R(im,71,48,2,17,"woodlight");R(im,26,59,44,3,"wood")
    P(im,{{22,14},{69,14},{81,23},{76,42},{21,42},{15,24}},"deepwood")
    R(im,22,17,48,22,"woodlight");R(im,23,17,46,3,"honey")
    R(im,24,34,44,4,"wood");R(im,69,20,10,18,"woodshadow")
    for x=31,62,10 do R(im,x,22,4,3,"goldwood") end
    R(im,79,25,13,7,"brassdark");R(im,79,25,13,2,"honey")
    R(im,4+dx,23,20-dx,5,"deepwood");R(im,5+dx,23,19-dx,2,"goldwood")
    O(im,2+dx,17,6,15,"woodshadow",2);R(im,3+dx,18,3,11,"honey")
    D.layer(s,"bellows handle and wood housing",im,frame)
  end
  D.tag(s,"pump",1,8,true);D.anchor(s,"grip_frame_1",5,25)
  D.save(s,"alchemy/bellows",false)
  s=D.sprite(56,48);D.frames(s,6,.12)
  for frame=1,6 do
    im=image(56,48)
    P(im,{{5,45},{3,33},{12,24},{11,13},{21,23},{28,4+frame%3*3},{34,20},{44,12},{43,29},{52,37},{49,46}},"brick")
    P(im,{{8,45},{8,33},{19,30},{21,17},{29,27},{34,16},{38,33},{47,34},{47,44}},"orange")
    P(im,{{16,45},{18,35},{24,37},{29,26},{34,34},{40,39},{39,45}},"yellow")
    P(im,{{24,45},{27,37},{31,39},{34,45}},"paleyellow")
    D.layer(s,"fire contact loop",im,frame)
  end
  D.tag(s,"fire",1,6,true);D.save(s,"alchemy/fire",false)
end

-- Six identities share an authored anatomical construction, never flattened
-- recolours: hair, age marks, face and accessories each have their own layer.
local identities={
 {id="travel",hair="hairbrown",shade="hairblack",light="brownlight",cloth="teal",clothdark="blue"},
 {id="life",hair="hairbrown",shade="hairblack",light="brownlight",cloth="leaf",clothdark="leafshade"},
 {id="business",hair="silver",shade="silvershadow",light="white",cloth="blue",clothdark="deepblue"},
 {id="food",hair="hairbrown",shade="hairblack",light="brownlight",cloth="red",clothdark="brick"},
 {id="adventure",hair="stone_light",shade="slate",light="silver",cloth="leafshade",clothdark="pine"},
 {id="magic",hair="lavender",shade="purple",light="mauve",cloth="purple",clothdark="ink"}
}
local function head(im,id,ox,oy,expression,side)
  local function rect(x,y,w,h,c) R(im,x+ox,y+oy,w,h,c) end
  local function ellipse(x,y,w,h,c) E(im,x+ox,y+oy,w,h,c) end
  local function poly(points,c)
    local p={};for _,v in ipairs(points) do p[#p+1]={v[1]+ox,v[2]+oy} end;P(im,p,c)
  end
  -- Back hair, individual silhouettes.
  ellipse(1,4,38,39,id.shade);ellipse(3,3,34,37,id.hair)
  if id.id=="travel" then
    poly({{2,25},{-2,34},{0,43},{5,46},{9,40},{8,30}},id.shade)
    poly({{33,24},{39,31},{40,40},{35,46},{30,42},{30,30}},id.shade)
    rect(1,31,4,9,id.hair);rect(3,41,4,3,"goldwood");rect(34,32,4,8,id.hair);rect(32,41,4,3,"goldwood")
  elseif id.id=="life" then
    ellipse(8,-3,19,15,id.shade);ellipse(10,-3,16,12,id.hair);rect(9,4,18,3,"white")
    rect(3,27,7,16,id.hair);rect(31,28,5,14,id.hair)
  elseif id.id=="food" then
    ellipse(-7,15,15,15,id.shade);ellipse(-5,16,12,12,id.hair)
    poly({{-5,13},{-10,9},{-11,17},{-4,19},{0,16},{-1,10}},"red")
  elseif id.id=="magic" then
    poly({{2,18},{-2,33},{1,43},{8,46},{12,36},{34,35},{39,44},{43,35},{39,17}},id.shade)
    rect(1,29,5,11,id.hair);rect(35,29,5,10,id.hair)
  elseif id.id=="adventure" then
    poly({{3,11},{1,3},{9,4},{12,-2},{18,1},{25,-1},{29,4},{36,2},{40,12}},id.shade)
  end
  -- Cheek/ear contour is shared in size, age details are independent.
  ellipse(4,14,34,28,"skinshadow");ellipse(6,13,30,27,"skin")
  ellipse(7,12,28,24,"skinlight");rect(11,15,19,12,"skinhi")
  ellipse(2,23,6,9,"skin");ellipse(33,23,6,8,"skin")
  poly({{5,16},{5,8},{12,3},{25,3},{34,8},{37,18},{32,23},{29,14},{24,17},{18,12},{11,19}},id.hair)
  poly({{7,9},{13,5},{24,5},{28,8},{16,8},{12,13},{7,14}},id.light)
  if id.id=="business" then
    ellipse(4,3,16,13,id.light);ellipse(14,1,17,11,id.light);ellipse(27,6,10,12,id.hair)
    rect(8,22,7,2,id.shade);rect(25,22,7,2,id.shade)
    poly({{15,33},{20,31},{24,33},{29,32},{27,36},{22,35},{17,36},{12,34}},"silvershadow")
    rect(9,32,3,1,"skinshadow");rect(30,32,2,1,"skinshadow")
  elseif id.id=="magic" then
    poly({{15,4},{25,4},{30,9},{28,17},{23,22},{20,19},{21,12},{12,14}},"goldhair")
    poly({{19,5},{25,6},{27,10},{25,14},{21,15},{23,9}},"honey")
  elseif id.id=="adventure" then
    poly({{5,10},{7,5},{12,7},{16,2},{20,6},{29,4},{33,10},{27,9},{22,16},{18,11},{13,17},{12,10}},id.light)
  end
  local eyeY=25
  if expression=="success" then
    rect(11,eyeY,5,1,"hairblack");rect(12,eyeY-1,3,1,"hairblack")
    rect(26,eyeY,5,1,"hairblack");rect(27,eyeY-1,3,1,"hairblack")
  else
    rect(12,eyeY,3,5,"hairblack");rect(27,eyeY,3,5,"hairblack")
    rect(13,eyeY,1,1,"white");rect(28,eyeY,1,1,"white")
    if expression=="miss" then rect(10,22,6,1,"hairblack");rect(25,21,7,1,"hairblack") end
  end
  rect(8,30,5,2,"rose");rect(30,30,4,2,"rose")
  rect(22,29,2,3,"skin");rect(19,35,5,1,"skinshadow")
  if expression=="success" then rect(19,34,6,3,"skinshadow");rect(20,34,4,1,"white") end
end
local function actor(id)
  local s=D.sprite(96,128);D.frames(s,14,.10)
  local function layer(name,im,frame)
    -- Deliberate material sharing, not an automatic nearest-color quantizer.
    local map={[D.c.skinhi]=D.c.skinlight,[D.c.paper]=D.c.cream,[D.c.goldwood]=D.c.honey}
    if id.id=="adventure" then map[D.c.wood]=D.c.woodshadow end
    for y=0,im.height-1 do for x=0,im.width-1 do
      local old=im:getPixel(x,y);if map[old] then im:drawPixel(x,y,map[old]) end
    end end
    D.layer(s,name,im,frame)
  end
  -- First eight are a smooth pump cycle. Frames 9/10 release, 11 error,
  -- 12 recover, 13/14 success. Feet and the handle remain fixed anchors.
  local pulls={0,2,5,8,10,8,5,2,1,0,0,0,0,0}
  for frame,dx in ipairs(pulls) do
    local im=image(96,128)
    local lean=(frame>=3 and frame<=6) and 1 or 0
    -- Stance: weight over both feet, knees mildly bent for the bellows.
    P(im,{{26,81},{63,81},{61,101},{68,119},{52,119},{45,99},{40,119},{23,119},{27,99}},"hairblack")
    P(im,{{29,86},{44,87},{42,101},{37,115},{26,115},{30,99}},"woodshadow")
    P(im,{{47,87},{60,86},{57,101},{64,115},{54,115},{47,99}},"wood")
    O(im,20,115,20,9,"hairblack",3);O(im,50,115,23,9,"hairblack",3)
    R(im,22,117,16,2,"woodlight");R(im,54,117,15,2,"woodlight")
    layer("legs / fixed foot anchors",im,frame)
    im=image(96,128)
    P(im,{{29+lean,45},{49+lean,43},{60+lean,49},{65,68},{61,94},{24,94},{21,70},{24,53}},"hairblack")
    P(im,{{29+lean,48},{49+lean,46},{57+lean,51},{61,68},{57,91},{28,91},{25,71},{27,54}},"cream")
    P(im,{{29,60},{34,49},{40,59},{48,47},{53,62},{56,91},{29,91}},id.clothdark)
    P(im,{{33,61},{47,60},{51,67},{51,86},{32,86}},id.cloth)
    R(im,27,67,31,4,"woodshadow");R(im,39,69,7,4,"goldwood")
    R(im,34,76,12,7,id.clothdark);R(im,35,76,10,1,"cream")
    P(im,{{31,46},{37,45},{42,52},{37,58},{33,53}},"paper")
    P(im,{{43,52},{48,46},{51,48},{47,58}},"honey")
    if id.id=="adventure" then P(im,{{33,47},{44,47},{42,53},{47,62},{41,61},{36,54}},"red") end
    layer("work shirt and tied apron",im,frame)
    im=image(96,128);head(im,id,23+lean,frame==14 and 5 or 4,frame>=13 and "success" or frame==11 and "miss" or "ready")
    layer("identity face and hair",im,frame)
    im=image(96,128)
    -- Both arms have distinct elbows; wrists finish at the moving grip.
    local hx=82+dx; local hy=78
    P(im,{{54,52},{63,53},{68,67},{hx-2,hy-6},{hx-4,hy+2},{59,75},{54,64}},"hairblack")
    P(im,{{56,55},{61,55},{65,70},{hx-5,hy-5},{hx-6,hy},{61,72},{57,65}},"cream")
    R(im,hx-10,hy-5,6,7,"honey")
    O(im,hx-4,hy-5,7,9,"skinshadow",2);O(im,hx-3,hy-4,6,7,"skinlight",2)
    R(im,hx,hy-2,3,1,"skinhi")
    P(im,{{25,56},{33,57},{47,72},{57,77},{hx-3,hy+2},{hx-2,hy+9},{54,88},{44,83},{27,72},{24,65}},"hairblack")
    P(im,{{27,59},{31,59},{45,75},{56,80},{hx-7,hy+4},{hx-7,hy+7},{55,85},{46,80},{29,70},{26,65}},"cream")
    L(im,34,68,44,78,"honey",2)
    R(im,hx-11,hy+3,6,6,"honey");O(im,hx-5,hy+2,8,8,"skinshadow",2)
    O(im,hx-4,hy+3,7,5,"skinlight",2);R(im,hx-2,hy+3,4,1,"skinhi")
    layer("sleeves elbows and contact hands",im,frame)
  end
  D.tag(s,"pump",1,8,true);D.tag(s,"release",9,10,false)
  D.tag(s,"miss",11,11,false);D.tag(s,"recover",12,12,false);D.tag(s,"success",13,14,false)
  D.anchor(s,"feet",46,124);D.anchor(s,"grip_frame_1",84,82)
  D.save(s,"alchemy/"..id.id,false)
end

local function shennong(id)
  local s=D.sprite(20,24);D.frames(s,14,.09)
  -- 8 run frames: left contact, down, passing, up, right contact, down,
  -- passing, up. Head/pelvis bobs only one native pixel; legs alternate.
  local feet={{{4,22},{15,21}},{{5,22},{13,20}},{{8,22},{10,19}},{{12,22},{6,20}},
    {{15,22},{4,21}},{{13,22},{5,20}},{{10,22},{8,19}},{{6,22},{12,20}}}
  local near_knees={{8,19},{8,20},{9,19},{12,18},{13,19},{12,20},{10,19},{8,18}}
  local far_knees={{11,18},{10,17},{7,18},{7,19},{6,18},{8,17},{12,18},{13,19}}
  for frame=1,14 do
    local im=image(20,24);local bob=(frame==2 or frame==6) and 1 or 0
    local pose=feet[math.min(frame,8)]
    if frame==9 then pose={{7,22},{12,22}};bob=0 end
    if frame==10 then pose={{6,20},{13,19}};bob=-1 end
    if frame==11 then pose={{7,21},{13,22}} end
    if frame>=12 then pose={{6,22},{13,22}} end
    -- Bamboo basket behind the body.
    R(im,2,10+bob,5,8,"woodshadow");R(im,2,10+bob,4,7,"goldwood")
    R(im,2,12+bob,4,1,"wood");R(im,2,15+bob,4,1,"wood")
    local knee=frame<=8 and far_knees[frame] or {8,19}
    L(im,8,16+bob,knee[1],knee[2],"hairblack",2)
    L(im,knee[1],knee[2],pose[2][1],pose[2][2]-1,"hairblack",2)
    R(im,pose[2][1]-1,pose[2][2],4,2,"woodshadow")
    knee=frame<=8 and near_knees[frame] or {11,19}
    L(im,11,16+bob,knee[1],knee[2],"goldwood",2)
    L(im,knee[1],knee[2],pose[1][1],pose[1][2]-1,"goldwood",2)
    R(im,pose[1][1]-1,pose[1][2],4,2,"hairblack")
    P(im,{{7,9+bob},{13,9+bob},{15,16+bob},{11,18+bob},{6,16+bob}},"hairblack")
    R(im,7,10+bob,6,6,id.cloth);R(im,7,15+bob,7,2,"cream")
    local handx=frame<=8 and (frame<=4 and 15-(frame-1) or 8+frame-5) or 14
    L(im,12,11+bob,handx,15+bob,"cream",2);R(im,handx,15+bob,2,2,"skinlight")
    -- Small native face, species/identity silhouette survives at 2x.
    O(im,5,1+bob,11,10,"hairblack",2);O(im,7,4+bob,10,7,"skinlight",2)
    P(im,{{5,6+bob},{5,2+bob},{8,bob},{13,bob},{16,3+bob},{15,6+bob},{11,4+bob},{8,7+bob}},id.hair)
    R(im,7,2+bob,6,1,id.light);R(im,14,6+bob,1,2,"hairblack")
    R(im,16,8+bob,2,1,"skin");R(im,12,10+bob,3,1,"skinshadow")
    if id.id=="travel" then R(im,4,6+bob,2,6,id.hair);R(im,4,11+bob,2,1,"goldwood") end
    if id.id=="life" then R(im,5,bob,4,3,id.hair);R(im,5,3+bob,4,1,"white") end
    if id.id=="business" then R(im,13,9+bob,4,1,"silvershadow") end
    if id.id=="food" then R(im,4,3+bob,3,3,id.hair);R(im,3,4+bob,2,2,"red") end
    if id.id=="adventure" then R(im,9,10+bob,5,2,"red");R(im,6,12+bob,2,3,"red") end
    if id.id=="magic" then P(im,{{10,1+bob},{14,2+bob},{14,5+bob},{11,7+bob},{12,3+bob},{9,3+bob}},"goldhair");R(im,4,6+bob,2,5,id.hair) end
    D.layer(s,"native 20x24 pose / contact feet",im,frame)
  end
  D.tag(s,"run",1,8,true);D.tag(s,"idle",9,9,true);D.tag(s,"jump",10,10,false)
  D.tag(s,"fall",11,11,false);D.tag(s,"land",12,12,false);D.tag(s,"recover",13,13,false);D.tag(s,"success",14,14,false)
  D.anchor(s,"feet",10,24);D.save(s,"shennong/"..id.id,false)
end

local function terrain()
  for part=0,2 do
    local s=D.sprite(500,300);local im=image(500,300)
    R(im,0,0,500,300,"skyhi");R(im,0,35,500,180,"sky")
    P(im,{{0,122},{23,115},{51,78},{63,67},{76,69},{90,88},{112,94},{143,81},{174,48},{184,43},{197,50},{213,76},{251,94},{285,82},{312,36},{325,30},{339,39},{360,67},{398,92},{439,69},{452,71},{473,93},{500,104},{500,300},{0,300}},"lightblue")
    P(im,{{0,170},{35,155},{67,129},{82,121},{106,125},{138,154},{176,153},{211,121},{242,99},{261,100},{287,119},{322,150},{357,146},{400,121},{422,117},{449,133},{480,151},{500,154},{500,300},{0,300}},"leaflit")
    P(im,{{0,228},{48,217},{78,201},{96,198},{128,211},{165,231},{199,227},{233,203},{261,195},{285,199},{318,215},{353,221},{401,208},{438,195},{460,198},{500,220},{500,300},{0,300}},"leaf")
    if part==0 then
      for n,x in ipairs({-13,88,344,468}) do
        -- Root flare, branching trunk and clustered canopy have authored
        -- silhouettes. They are not giant concentric circles.
        P(im,{{x+1,45},{x+17,45},{x+15,143},{x+20,216},{x+30,237},{x+19,234},{x+11,227},{x+2,236},{x-10,239},{x-2,222},{x+2,155}},"leafshade")
        P(im,{{x+5,74},{x+11,68},{x+9,151},{x+13,226},{x+7,221},{x+5,150}},"leaf")
        P(im,{{x+3,112},{x-30,76},{x-42,74},{x-29,64},{x+9,96},{x+26,76},{x+51,58},{x+57,61},{x+35,88},{x+15,117}},"leafshade")
        local lobes={{-58,-10,65,59},{-26,-23,73,63},{17,-7,69,58},{-49,26,67,47},{-6,23,77,47},{44,15,53,42}}
        for _,v in ipairs(lobes) do E(im,x+v[1],v[2]+n%2*8,v[3],v[4],"pine") end
        for _,v in ipairs({{-55,-15,67,58},{-17,-18,70,57},{30,-9,53,56},{-34,20,49,34},{8,22,52,32}}) do
          E(im,x+v[1],v[2]+n%2*8,v[3],v[4],"leafshade")
        end
        for _,v in ipairs({{-45,2,29,13},{-10,-1,37,17},{23,5,28,12},{-22,29,25,8},{34,31,21,7}}) do
          E(im,x+v[1],v[2]+n%2*8,v[3],v[4],"leaf")
        end
      end
    elseif part==1 then
      P(im,{{0,263},{144,247},{252,259},{367,246},{500,264},{500,300},{0,300}},"teal")
      L(im,40,272,132,272,"lightblue",2);L(im,290,281,389,281,"lightblue",2)
    end
    D.layer(s,"quiet distant landscape",im);D.save(s,"shennong/background-"..part,true)
  end
  for _,name in ipairs({"forest","creek","ridge"}) do
    local s=D.sprite(32,32);local im=image(32,32)
    R(im,0,0,32,32,"woodshadow");R(im,0,0,32,3,"leafshade");R(im,0,0,32,1,"leaflit")
    R(im,0,3,32,2,"woodlight");R(im,0,5,32,27,"wood")
    P(im,{{3,12},{6,9},{11,10},{12,13},{9,16},{4,15}},"woodshadow")
    P(im,{{21,24},{24,22},{29,24},{28,27},{22,28}},"woodshadow")
    R(im,6,9,4,1,"woodlight");R(im,24,22,3,1,"woodlight")
    R(im,1,20,7,1,"woodlight");R(im,17,8,6,1,"woodlight")
    if name~="forest" then
      -- Stone has the same one-pixel grid; no runtime resampling.
      for y=4,31 do for x=0,31 do
        local c=im:getPixel(x,y)
        if c==D.c.wood then im:drawPixel(x,y,D.c.slate)
        elseif c==D.c.woodlight then im:drawPixel(x,y,D.c.stone)
        elseif c==D.c.goldwood then im:drawPixel(x,y,D.c.stone_light)
        elseif c==D.c.woodshadow then im:drawPixel(x,y,D.c.charcoal) end
      end end
    end
    D.layer(s,"static world tile",im);D.save(s,"shennong/"..name,true)
  end
  local s=D.sprite(16,16);local im=image(16,16)
  P(im,{{0,15},{1,8},{6,1},{11,0},{15,6},{16,15}},"charcoal")
  P(im,{{2,14},{3,8},{7,3},{11,2},{14,7},{14,14}},"stone")
  P(im,{{3,8},{7,3},{10,3},{8,8}},"stone_light")
  P(im,{{8,9},{14,7},{14,14},{7,14}},"slate")
  D.layer(s,"rock silhouette",im);D.save(s,"shennong/rock",true)
  for _,spec in ipairs({{14,8},{14,11},{15,11},{14,10},{15,10}}) do
    local w,h=spec[1],spec[2];s=D.sprite(w,h);im=image(w,h)
    P(im,{{0,h-1},{1,math.floor(h*.4)},{5,0},{w-4,0},{w-1,math.floor(h*.45)},{w,h-1}},"charcoal")
    P(im,{{2,h-2},{2,math.floor(h*.5)},{6,1},{w-4,1},{w-2,math.floor(h*.5)},{w-2,h-2}},"stone")
    P(im,{{3,math.floor(h*.5)},{6,1},{w-5,1},{w-6,math.floor(h*.5)}},"stone_light")
    P(im,{{w-7,math.floor(h*.55)},{w-2,math.floor(h*.5)},{w-2,h-2},{w-7,h-2}},"slate")
    D.layer(s,"rock fitted to collision footprint",im);D.save(s,"shennong/rock-"..w.."x"..h,true)
  end
  s=D.sprite(16,12);im=image(16,12)
  R(im,0,2,16,9,"deepwood");R(im,0,3,16,6,"woodshadow")
  L(im,0,3,6,3,"wood",2);L(im,6,4,14,4,"wood",2)
  R(im,3,8,7,1,"wood");P(im,{{10,3},{12,0},{15,0},{14,4}},"woodshadow")
  D.layer(s,"low branch tile",im);D.save(s,"shennong/branch",true)
  s=D.sprite(20,32);im=image(20,32)
  R(im,6,3,3,28,"woodshadow");R(im,6,3,1,27,"goldwood")
  P(im,{{3,3},{16,3},{20,8},{16,12},{3,12}},"woodshadow")
  P(im,{{4,4},{15,4},{18,8},{15,10},{4,10}},"cream")
  R(im,7,7,7,1,"leafshade");L(im,12,5,15,8,"leafshade");L(im,15,8,12,10,"leafshade")
  R(im,4,30,9,2,"pine")
  D.layer(s,"way marker",im);D.save(s,"shennong/marker",true)
end

ui();workshop();terrain()
for _,id in ipairs(identities) do actor(id);shennong(id) end
print("P1 authored source generation complete")
