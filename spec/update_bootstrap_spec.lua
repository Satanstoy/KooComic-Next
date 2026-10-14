package.path="./koocomic.koplugin/?.lua;"..package.path
local loaded,Bootstrap=pcall(require,"koobone.update_bootstrap")
assert(loaded,"updates must recover module-load and initialization failures before confirming startup")
local rollback,shown=0,{}
local function options(loader)
    return {loader=loader,prepare=function() return {pending=true,rollback=function() rollback=rollback+1;return true end} end,
        fallback=function(recovered) return {recovered=recovered,new=function(self) return self end} end}
end
local result=Bootstrap.load(options(function() error("private module error") end))
assert(result.recovered and rollback==1)
result=Bootstrap.load(options(function() return "not a plugin" end))
assert(result.recovered and rollback==2,"invalid module return must follow the same recovery path")
local class={init=function() error("private init error") end,new=function(self) return self end}
class=Bootstrap.load(options(function() return class end))
local instance={};class.init(instance)
assert(rollback==3 and instance.recovered,"failed init must recover without propagating private errors")
local successful=false
class=Bootstrap.load(options(function() return {init=function() successful=true end,new=function(self) return self end} end))
class.init({});assert(successful and rollback==3)
class=Bootstrap.load(options(function() return {init=function() end,new=function() error("private constructor detail") end} end))
assert(class:new().recovered and rollback==4,"constructor failure must recover too")
result=Bootstrap.load(options(function() return {init=function() end} end))
assert(result.recovered and rollback==5,"missing constructor must not escape KOReader's startup guard")
local plain={init=function() error("ordinary unrelated startup error") end}
local ok=pcall(Bootstrap.load,{loader=function() return plain end,prepare=function() return {} end})
assert(ok and not pcall(plain.init,{}),"normal non-update errors must remain visible to KOReader")
print("update startup bootstrap spec: OK")
