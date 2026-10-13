package.path="./koocomic.koplugin/?.lua;"..package.path
local loaded,Staging=pcall(require,"koobone.update_staging")
assert(loaded,"update downloads and extraction need a durable owned staging lease")
local paths={work="work",archive="archive",stage="stage"}
local artifacts,record={},nil
local b={paths=paths,exists=function(_,path) return artifacts[path]~=nil end,identity=function(_,path) return artifacts[path] end,
    loadLease=function() return record end,saveLease=function(_,value) record=value;return true end,
    clearLease=function() record=nil;return true end,
    createDirectory=function(_,path) if artifacts[path] then return nil end;artifacts[path]="work inode";return true end,
    remove=function(_,path,expected) if artifacts[path]~=expected then return nil end;artifacts[path]=nil;return true end,
    move=function(_,source,target) if artifacts[target] then return nil end;artifacts[target],artifacts[source]=artifacts[source],nil;return true end}
b.files={exclusiveWriter=function(_,path)
    if artifacts[path] then return nil end;artifacts[path]="archive inode"
    return {identity=function() return "archive inode" end,write=function() return true end,close=function() return true end}
end}
local lease=Staging:new{backend=b}
assert(lease:begin());assert(lease:createWork());local writer=assert(lease:openArchive());assert(writer:write("fixture"));writer:close()
assert(#record.assets==2,"ownership must be persisted before archive bytes are written")
artifacts["work/koocomic.koplugin"]="candidate inode"
assert(lease:handoff());assert(artifacts.stage=="candidate inode" and #record.assets==3)
assert(Staging:new{backend=b}:cleanup() and not artifacts.work and not artifacts.stage and not record,
    "reopened staging must safely retire all owned transient assets")
artifacts.work="external inode"
assert(not lease:begin() and artifacts.work=="external inode","unowned work directories must not be removed")
artifacts.work=nil
assert(lease:begin());assert(lease:createWork());artifacts.work="replacement inode"
assert(not lease:cleanup() and artifacts.work=="replacement inode")
print("update staging spec: OK")
