package.path="./koocomic.koplugin/?.lua;"..package.path
local ok,Package=pcall(require,"koobone.update_package")
assert(ok,"updater must use a bounded regular-file-only package extractor")
local entries,output,reads={}, {},0
local reader={open=function() return true end,close=function() end,iterate=function()
    local index=0;return function() index=index+1;return entries[index] end end,
    extractToMemory=function(_,path) reads=reads+1;for _,entry in ipairs(entries) do if entry.path==path then return entry.data end end end}
local files={mkdir=function() return true end,isSafe=function() return true end,
    exclusiveWriter=function(_,path) if output[path] then return nil end
        output[path]="";return {write=function(_,data) output[path]=data;return true end,close=function() return true end} end,
    sync=function() return true end}
local package=Package:new{reader=reader,files=files,max_bytes=8,max_file_bytes=4,max_entries=4}
local function extract(values) entries=values;output={};reads=0;return package:extract("fixture.zip","/stage") end
assert(extract({{path="koocomic.koplugin/",mode="directory",size=0},
    {path="koocomic.koplugin/main.lua",mode="file",size=4,data="code"}}))
assert(output["/stage/koocomic.koplugin/main.lua"]=="code")
for _,mode in ipairs({"link","socket","named pipe","other"}) do
    assert(not extract({{path="koocomic.koplugin/link",mode=mode,size=0}}) and reads==0)
end
for _,path in ipairs({"koocomic.koplugin/../outside","koocomic.koplugin//main.lua","koocomic.koplugin/./main.lua",
    "/koocomic.koplugin/main.lua","koocomic.koplugin\\main.lua","koocomic.koplugin/book.epub","koocomic.koplugin/koobone.lua"}) do
    assert(not extract({{path=path,mode="file",size=1,data="x"}}),path)
end
local file={path="koocomic.koplugin/main.lua",mode="file",size=1,data="x"}
reader.verifyEnd=function() return false end
assert(not extract({file}),"CRC/EOF failure must reject resource data even when declared size matches")
reader.verifyEnd=function() return true end
assert(not extract({file,file}),"duplicate entries must not overwrite earlier data")
assert(not extract({{path="koocomic.koplugin/main.lua",mode="file",size=5,data="12345"}}) and reads==0)
assert(not extract({{path="koocomic.koplugin/main.lua",mode="file",size=0/0}}))
local many={}
for index=1,5 do many[index]={path="koocomic.koplugin/dir"..index,mode="directory",size=0} end
assert(not extract(many),"entry count budget must include directories")
assert(not extract({}),"empty archives are not installable packages")
assert(not extract({{path="koocomic.koplugin/a",mode="file",size=4,data="1234"},
    {path="koocomic.koplugin/b",mode="file",size=4,data="1234"},{path="koocomic.koplugin/c",mode="file",size=1,data="x"}}))
assert(not extract({{path="koocomic.koplugin/main.lua",mode="file",size=4,data="x"}}),"short data cannot pass size validation")
files.sync=function() return nil,"sync failed" end
assert(not extract({file}),"failed output fsync must abort installation")
local closed=false
files.exclusiveWriter=function() return {write=function() error("I/O exception") end,
    close=function() closed=true;return true end} end
assert(not extract({file}) and closed,"write exceptions must still close the exclusive output")
print("update package spec: OK")
