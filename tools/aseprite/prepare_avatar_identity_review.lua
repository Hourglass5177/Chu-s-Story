-- Source-faithful pixel identity studies. These are review studies, not finished
-- gameplay animations. Original illustrations are read only and remain intact.
local root=app.params.root or "F:/Documents/楚物志"
local out=root.."/InheritanceTasks/Art/Pixel/v2/review/avatar-identity-r2"
app.fs.makeAllDirectories(out)
local entries={
  {id="travel",name="旅行博主",crop={160,0,952,1844}},
  {id="life",name="生活博主",crop={123,0,527,1090}},
  {id="business",name="商业博主",crop={585,0,2352,5232}},
  {id="food",name="美食博主",crop={103,0,854,1536}},
  {id="adventure",name="探险博主",crop={188,0,800,1844}},
  {id="magic",name="魔术博主",crop={379,0,2742,5232}},
}
local pc=app.pixelColor
for _,e in ipairs(entries) do
  if not app.params.avatar or app.params.avatar==e.id then
    local s=assert(app.open(root.."/arts/素材合集/sprite及立绘/Sprite/角色/"..e.name..".png"))
    s:crop(Rectangle(e.crop[1],e.crop[2],e.crop[3],e.crop[4]))
    local h=144
    local w=math.floor(s.width*h/s.height+.5)
    app.command.SpriteSize{ui=false,width=w,height=h,method="bilinear"}
    local im=Image(s)
    for it in im:pixels() do
      local p=it()
      if pc.rgbaA(p)<160 then it(0)
      else it(pc.rgba(pc.rgbaR(p),pc.rgbaG(p),pc.rgbaB(p),255)) end
    end
    s:newCel(s.layers[1],1,im,Point(0,0))
    s.layers[1].name="original identity pixel study - retouch pending"
    app.command.ColorQuantization{ui=false,withAlpha=true,maxColors=24,algorithm="octree"}
    app.command.ChangePixelFormat{ui=false,format="indexed",dithering="none"}
    s:saveAs(out.."/"..e.id.."-study.aseprite")
    s:saveCopyAs(out.."/"..e.id.."-study.png")
    app.command.SpriteSize{ui=false,width=w*4,height=h*4,method="nearest-neighbor"}
    s:saveCopyAs(out.."/"..e.id.."-study-4x.png")
    print("Identity underpainting "..e.id.." "..w.."x"..h)
    s:close()
  end
end
