-- Editable composition uses the same layered authored sources as the game.
local root=app.params.root or "F:/Documents/楚物志"
local D=dofile(root.."/tools/aseprite/pixel_drawing.lua")
local s
local function add(name,path,x,y)
  local source=app.open(D.art.."/source/"..path..".aseprite")
  local flat=Image(source)
  local canvas=D.img(500,300)
  canvas:drawImage(flat,Point(x,y))
  source:close()
  D.layer(s,name,canvas)
end
for _,id in ipairs({"travel","life","business","food","adventure","magic"}) do
  s=D.sprite(500,300)
  add("workshop", "alchemy/background",0,0)
  add("bellows with stool", "alchemy/bellows",171,168)
  add(id.." blogger work clothes", "alchemy/"..id,92,111)
  add("fire behind the arch", "alchemy/fire",311,161)
  add("furnace", "alchemy/furnace",263,54)
  D.save(s,"alchemy/cover-"..id,true)
end
