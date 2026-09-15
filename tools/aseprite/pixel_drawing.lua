-- Deterministic indexed-pixel drawing helpers for the authored Chu assets.
-- All artwork is created as editable Aseprite layers; no chroma-key extraction.
local M = {}
local root = app.params.root or "F:/Documents/楚物志"
M.root = root
M.art = root .. "/InheritanceTasks/Art/Pixel/v2"
local f = assert(io.open(M.art .. "/palette.json", "r"))
local raw = f:read("*a"); f:close()
M.palette = Palette(49)
M.palette:setColor(0, Color{r=0,g=0,b=0,a=0})
M.c = {}; local i=1
for name, hex in raw:gmatch('"([%w_]+)"%s*:%s*"(%x%x%x%x%x%x)"') do
  M.c[name] = i
  M.palette:setColor(i, Color{r=tonumber(hex:sub(1,2),16),g=tonumber(hex:sub(3,4),16),b=tonumber(hex:sub(5,6),16),a=255})
  i=i+1
end
assert(i==49, "Expected the reviewed 48-color master palette")
function M.sprite(w,h)
  local s=Sprite(w,h,ColorMode.INDEXED); s:setPalette(M.palette)
  s.transparentColor=0; s.gridBounds=Rectangle(0,0,1,1)
  s:deleteLayer(s.layers[1]); return s
end
function M.img(w,h) return Image(w,h,ColorMode.INDEXED) end
function M.p(im,x,y,c)
  x=math.floor(x); y=math.floor(y)
  if x>=0 and y>=0 and x<im.width and y<im.height then im:drawPixel(x,y,type(c)=="string" and assert(M.c[c],c) or c) end
end
function M.rect(im,x,y,w,h,c)
  for yy=math.floor(y),math.floor(y+h-1) do for xx=math.floor(x),math.floor(x+w-1) do M.p(im,xx,yy,c) end end
end
function M.line(im,x0,y0,x1,y1,c,width)
  x0=math.floor(x0);y0=math.floor(y0);x1=math.floor(x1);y1=math.floor(y1)
  local dx=math.abs(x1-x0); local sx=x0<x1 and 1 or -1
  local dy=-math.abs(y1-y0); local sy=y0<y1 and 1 or -1; local err=dx+dy
  while true do
    M.rect(im,x0,y0,width or 1,width or 1,c)
    if x0==x1 and y0==y1 then break end
    local e=2*err
    if e>=dy then err=err+dy;x0=x0+sx end
    if e<=dx then err=err+dx;y0=y0+sy end
  end
end
function M.poly(im,pts,c)
  local lo,hi=im.height,0
  for _,v in ipairs(pts) do lo=math.min(lo,v[2]);hi=math.max(hi,v[2]) end
  for y=math.floor(lo),math.floor(hi) do
    local hits={}; local j=#pts
    for k=1,#pts do
      local a,b=pts[k],pts[j]
      if (a[2]<=y and b[2]>y) or (b[2]<=y and a[2]>y) then
        hits[#hits+1]=a[1]+(y-a[2])*(b[1]-a[1])/(b[2]-a[2])
      end
      j=k
    end
    table.sort(hits)
    for k=1,#hits,2 do if hits[k+1] then
      for x=math.ceil(hits[k]),math.floor(hits[k+1]) do M.p(im,x,y,c) end
    end end
  end
end
function M.ellipse(im,x,y,w,h,c)
  for yy=0,h-1 do for xx=0,w-1 do
    if ((xx+.5-w/2)/(w/2))^2+((yy+.5-h/2)/(h/2))^2<=1 then M.p(im,x+xx,y+yy,c) end
  end end
end
function M.round(im,x,y,w,h,c,r)
  r=r or 3
  M.rect(im,x+r,y,w-2*r,h,c);M.rect(im,x,y+r,w,h-2*r,c)
  M.ellipse(im,x,y,r*2,r*2,c);M.ellipse(im,x+w-r*2,y,r*2,r*2,c)
  M.ellipse(im,x,y+h-r*2,r*2,r*2,c);M.ellipse(im,x+w-r*2,y+h-r*2,r*2,r*2,c)
end
function M.layer(s,name,im,frame)
  local layer
  for _,l in ipairs(s.layers) do if l.name==name then layer=l end end
  if not layer then layer=s:newLayer();layer.name=name end
  return s:newCel(layer,frame or 1,im,Point(0,0))
end
function M.frames(s,n,seconds)
  for k=2,n do s:newEmptyFrame(k) end
  for _,fr in ipairs(s.frames) do fr.duration=seconds or .1 end
end
function M.tag(s,name,a,b,loop)
  local t=s:newTag(a,b);t.name=name;t.data=loop and "loop" or "once; hold final frame"
end
function M.anchor(s,name,x,y)
  local sl=s:newSlice(Rectangle(x,y,1,1));sl.name=name;sl.pivot=Point(0,0)
end
function M.save(s,name,static)
  app.fs.makeAllDirectories(M.art.."/source/"..app.fs.filePath(name))
  s:saveAs(M.art.."/source/"..name..".aseprite")
  if static then
    app.fs.makeAllDirectories(M.art.."/runtime/"..app.fs.filePath(name))
    s:saveCopyAs(M.art.."/runtime/"..name..".png")
  end
  print("Authored "..name.." ("..s.width.."x"..s.height..", "..#s.layers.." layers, "..#s.frames.." frames)")
  s:close()
end
return M
