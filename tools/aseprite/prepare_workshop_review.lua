-- Candidate-only preparation of the generated medicinal workshop.
-- The source image and production art/palette are never modified.
-- Aseprite v1.3.18.5: native resize, octree palette and no-dither conversion.
local root=app.params.root or "F:/Documents/楚物志"
local dir=root.."/InheritanceTasks/Art/Pixel/v2/review/generated-workshop"
local revision=app.params.revision or "r1"
local source=dir.."/workshop-source-"..revision..".png"
local function write(path,value)
  local f=assert(io.open(path,"w"));f:write(json.encode(value));f:close()
end
local function color_distance(a,b)
  return (a.red-b.red)^2+(a.green-b.green)^2+(a.blue-b.blue)^2
end
local function in_cleanup_region(x,y)
  -- Quiet plaster and open ground only. Preserve instrument, herbs and fire.
  return (x>=147 and x<290 and y>=36 and y<73)
      or (x>=96 and x<390 and y>=224 and y<287)
end
local function slice(s,name,x,y,w,h,data)
  local sl=s:newSlice(Rectangle(x,y,w,h));sl.name=name;sl.data=data
end
local report={source=source,target_size={500,300},resize="bilinear to native, nearest-neighbor previews",
  quantization="octree",dithering="none",status="candidate only; visual review required",variants={}}

for _,count in ipairs({48,64}) do
  local opened=assert(app.open(source));app.activeSprite=opened
  report.source_size={opened.width,opened.height}
  app.command.SpriteSize{ui=false,width=500,height=300,method="bilinear"}
  app.command.ColorQuantization{ui=false,withAlpha=false,maxColors=count,useRange=false,algorithm="octree"}
  app.command.ChangePixelFormat{ui=false,format="indexed",dithering="none",rgbmap="octree",fitCriteria="rgb"}
  assert(opened.width==500 and opened.height==300 and opened.colorMode==ColorMode.INDEXED)
  local from=opened.cels[1].image
  local actual_count=#opened.palettes[1]
  assert(actual_count<=count,"Quantizer exceeded the requested palette budget")
  local palette=Palette(actual_count+1);palette:setColor(0,Color{r=0,g=0,b=0,a=0})
  for i=0,actual_count-1 do palette:setColor(i+1,opened.palettes[1]:getColor(i)) end
  local base=Image(500,300,ColorMode.INDEXED)
  for y=0,299 do for x=0,499 do base:drawPixel(x,y,from:getPixel(x,y)+1) end end
  opened:close()

  local s=Sprite(500,300,ColorMode.INDEXED);s:setPalette(palette);s.transparentColor=0
  s:deleteLayer(s.layers[1]);s.gridBounds=Rectangle(0,0,1,1)
  local layer=s:newLayer();layer.name="01 quantized generated source / unretouched"
  s:newCel(layer,1,base,Point(0,0))
  local prefix=dir.."/workshop-"..revision.."-"..count
  s:saveCopyAs(prefix.."-before-cleanup.png")

  local delta=Image(500,300,ColorMode.INDEXED);local changed={}
  for y=1,298 do for x=1,498 do if in_cleanup_region(x,y) then
    local original=base:getPixel(x,y);local seen={};local same=0
    for dy=-1,1 do for dx=-1,1 do if dx~=0 or dy~=0 then
      local c=base:getPixel(x+dx,y+dy);seen[c]=(seen[c] or 0)+1
      if c==original then same=same+1 end
    end end end
    if same==0 then
      local candidate=nil;local most=0
      for c,n in pairs(seen) do if n>most then candidate=c;most=n end end
      if most>=6 and color_distance(palette:getColor(original),palette:getColor(candidate))<=2700 then
        delta:drawPixel(x,y,candidate)
        changed[#changed+1]={x=x,y=y,from_index=original,to_index=candidate}
      end
    end
  end end end
  layer=s:newLayer();layer.name="02 reversible isolated-color cleanup / quiet surfaces only"
  s:newCel(layer,1,delta,Point(0,0))
  layer=s:newLayer();layer.name="03 reserved for reviewed contact/occlusion corrections (empty)"
  layer.isVisible=false
  if revision=="r1" then
  slice(s,"furnace body (baked source)",298,73,137,145,"Candidate only: do not add the old furnace over this.")
  slice(s,"fire and medicine pot opening",339,131,69,48,"Fire/medicine vessel currently baked into background.")
  slice(s,"bellows body (baked source)",215,149,90,61,"Motion requires an independently reviewed moving section and clean plate.")
  slice(s,"bellows grip target",158,154,22,12,"Proposed hand contact near (165,160).")
  slice(s,"proposed actor feet",107,211,31,3,"Proposed native center (123,213); actual new sprite must be tested.")
  slice(s,"proposed actor occupied region",77,94,97,122,"Actor in front of rear table, left of bellows. No avatar painted here.")
  else
    slice(s,"furnace body (baked source)",285,76,147,156,"Generated medicinal workshop, illustrative form; fire still baked into source.")
    slice(s,"clear working space",88,96,200,146,"No bellows in revised source; compose independent actor and bellows here.")
    slice(s,"quiet lower HUD area",80,272,354,25,"Keep native UI high contrast.")
  end
  s.data="Generated dedicated medicinal workshop candidate. Source retained separately. No scene replacement; anatomy, mechanics and heritage form unverified."
  s:saveAs(prefix..".aseprite")
  s:saveCopyAs(prefix..".png")
  local colors={};for i=1,actual_count do local c=palette:getColor(i);colors[#colors+1]=string.format("#%02x%02x%02x",c.red,c.green,c.blue) end
  report.variants[#report.variants+1]={color_budget=count,actual_palette_colors=actual_count,palette=colors,cleanup_count=#changed,cleanup_pixels=changed,
    aseprite=prefix..".aseprite",png=prefix..".png"}
  -- Display preview is a copy, never saved back over native source.
  local preview=Sprite(s);app.activeSprite=preview
  app.command.SpriteSize{ui=false,width=1000,height=600,method="nearest-neighbor"}
  preview:saveCopyAs(prefix.."-2x.png");preview:close();s:close()
  local reopened=assert(app.open(prefix..".aseprite"))
  local reopened_layers={}
  for _,l in ipairs(reopened.layers) do reopened_layers[#reopened_layers+1]={name=l.name,visible=l.isVisible} end
  report.variants[#report.variants].reopened_layers=reopened_layers
  assert(#reopened_layers==3,"Layered candidate did not preserve its three layers")
  reopened:close()
end
write(dir.."/preparation-report"..(revision=="r1" and "" or "-"..revision)..".json",report)
print("Workshop candidates: 48 and 64 colors, editable layers, native500x300 and nearest2x.")
