-- Synthetic toolchain fixture. This is not game artwork or an art-quality test.
local output = assert(app.params["output"], "Pass --script-param output=<directory>")
local sprite = Sprite(16, 16, ColorMode.INDEXED)
local palette = Palette(4)
palette:setColor(0, Color{r=0, g=0, b=0, a=0})
palette:setColor(1, Color{r=44, g=39, b=47, a=255})
palette:setColor(2, Color{r=209, g=154, b=75, a=255})
palette:setColor(3, Color{r=247, g=230, b=194, a=255})
sprite:setPalette(palette)
sprite.transparentColor = 0

local body = sprite.layers[1]
body.name = "body"
local detail = sprite:newLayer()
detail.name = "detail"
local base = Image(16, 16, ColorMode.INDEXED)
for y=5,13 do
  for x=4,11 do base:drawPixel(x,y,1) end
end
sprite:newCel(body, 1, base, Point(0,0))
local mark = Image(16, 16, ColorMode.INDEXED)
for y=6,9 do
  for x=6,9 do mark:drawPixel(x,y,2) end
end
sprite:newCel(detail, 1, mark, Point(0,0))
sprite:newFrame(1)
local moved = mark:clone()
moved:drawPixel(7,6,3)
sprite:newCel(detail, 2, moved, Point(0,0))
sprite.frames[1].duration = 0.1
sprite.frames[2].duration = 0.15
local tag = sprite:newTag(1,2)
tag.name = "fixture_loop"
local anchor = sprite:newSlice(Rectangle(0,0,16,16))
anchor.name = "feet"
anchor.pivot = Point(8,14)
anchor.data = "toolchain-test"
sprite:saveAs(output .. "/fixture.aseprite")
sprite:close()
local reopened = assert(app.open(output .. "/fixture.aseprite"))
assert(#reopened.layers == 2, "layers not preserved")
assert(#reopened.frames == 2, "frames not preserved")
assert(reopened.tags[1].name == "fixture_loop", "tag not preserved")
assert(reopened.slices[1].pivot.x == 8 and reopened.slices[1].pivot.y == 14, "pivot not preserved")
assert(reopened.palettes[1]:getColor(2).red == 209, "palette not preserved")
print("ASEPRITE_TOOLCHAIN_FIXTURE_OK " .. tostring(app.version) .. " api=" .. app.apiVersion)
