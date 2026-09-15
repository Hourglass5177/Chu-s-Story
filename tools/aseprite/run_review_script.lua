-- Preserve actionable Lua errors even for the Windows GUI-subsystem executable.
local root=app.params.root or "F:/Documents/楚物志"
local target=assert(app.params.target,"Pass target=<relative Lua script>")
local ok,result=xpcall(function() return dofile(root.."/"..target) end,debug.traceback)
app.fs.makeAllDirectories(root.."/artifacts/pixel-v2")
local f=assert(io.open(root.."/artifacts/pixel-v2/last-lua-run.log","w"))
f:write(ok and ("OK "..target) or tostring(result));f:close()
if not ok then error(result) end
