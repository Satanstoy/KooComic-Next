require("setupkoenv")
local root=assert(arg[1]);package.path=root.."/koocomic.koplugin/?.lua;"..package.path
local cases={"module","init","prepared","tampered","legacy_module","legacy_init","confirmed_retired","entry_bootstrap_error","entry_bootstrap_api","entry_bootstrap_tampered"}
if not arg[2] then
    for _,case in ipairs(cases) do
        assert(os.execute(string.format("./luajit %q %q %q",root.."/spec/koreader_update_bootstrap_integration.lua",root,case))==0)
    end
    print("KOReader cold-process startup recovery matrix: OK");return
end
local ffi=require("ffi");require("ffi/posix_h")
local directory="/tmp/koocomic-bootstrap-"..tonumber(ffi.C.getpid())
local Files=require("koobone.preprocess_files")
local files=Files:new{roots={directory,root}};assert(files:mkdir(directory))
local Bootstrap=require("koobone.update_bootstrap")
assert(type(Bootstrap.prepare)=="function","startup must recover through verified old modules before new Settings or dependencies load")
for _,failure in ipairs({arg[2]}) do
    local plugin=directory.."/"..failure..".koplugin"
    local function code(path,version)
        assert(files:mkdir(path));assert(files:mkdir(path.."/koobone"))
        assert(files:write(path.."/main.lua","return {}"))
        assert(files:write(path.."/koobone/plugin_version.lua",'return {product_id="koocomic-next",version="'..version..'"}'))
        for _,name in ipairs({"update_transaction","update_files","preprocess_files","settings_store"}) do
            assert(files:write(path.."/koobone/"..name..".lua",assert(files:read(root.."/koocomic.koplugin/koobone/"..name..".lua"))))
        end
    end
    code(plugin,"0.4.1");code(plugin..".next-stage","0.5.0")
    local settings=require("koobone.settings"):new(directory.."/"..(failure:match("^entry_") and "koocomic" or failure)..".lua")
    settings.data.ui.series_style="ribbon";assert(settings:flush())
    local backend=require("koobone.update_files"):new{plugin_dir=plugin,settings=settings}
    local tx=require("koobone.update_transaction"):new{backend=backend,paths=backend.paths}
    assert(tx:install("0.4.1","0.5.0",function() settings.data.ui.series_style="stack";return settings:flush() end))
    if failure:match("^legacy_") then
        local record=assert(backend:load());record.recovery_hashes=nil;assert(backend:save(record))
    end
    if failure=="prepared" then local record=assert(backend:load());record.phase="prepared";assert(backend:save(record)) end
    if failure=="tampered" then assert(files:write(backend.paths.backup.."/koobone/update_files.lua",'error("must never execute")')) end
    if failure=="confirmed_retired" then
        assert(tx:confirm("0.5.0"));assert(backend:remove(backend.paths.backup,backend:identity(backend.paths.backup)))
    end
    local original_path=package.path
    local original_backend=package.loaded["koobone.update_files"]
    local imports=0
    local options={plugin_dir=plugin,settings_path=settings.path,
        loader=function()
            imports=imports+1
            if failure=="module" or failure=="legacy_module" then error("private module detail") end
            return {init=function() if failure~="confirmed_retired" then error("private init detail") end end,
                new=function(self) return self end}
        end,fallback=function(recovered) return {recovered=recovered} end}
    local result
    if failure:match("^entry_") then
        ffi.C.setenv("SDL_VIDEODRIVER","dummy",1)
        G_defaults=require("luadefaults"):open()
        G_reader_settings=require("luasettings"):wrap{sdl_window={width=600,height=800}}
        local Device=require("device");require("document/canvascontext"):init(Device)
        assert(files:write(plugin.."/main.lua",assert(files:read(root.."/koocomic.koplugin/main.lua"))))
        assert(files:write(plugin.."/koobone/update_bootstrap.lua",failure=="entry_bootstrap_api" and "return {}" or 'error("broken new bootstrap")'))
        if failure=="entry_bootstrap_tampered" then
            assert(files:write(backend.paths.backup.."/koobone/update_files.lua",'error("unverified recovery must not execute")'))
        end
        package.path=plugin.."/?.lua;"..original_path
        package.loaded["koobone.update_bootstrap"]=nil
        local old_storage=require("datastorage")
        package.loaded.datastorage=setmetatable({getSettingsDir=function() return directory end},{__index=old_storage})
        local ok,value=pcall(dofile,plugin.."/main.lua")
        package.loaded.datastorage=old_storage
        package.path=original_path
        assert(ok and type(value)=="table" and value.restart_required,"real main must survive Bootstrap load/API failure: "..tostring(value))
        if failure=="entry_bootstrap_tampered" then
            assert(backend:validate(plugin,"0.5.0"),"modified recovery code must remain unexecuted")
        else
            assert(backend:validate(plugin,"0.4.1"),"real entry must restore the verified previous plugin")
            assert(backend:load().phase=="rolled_back" and require("koobone.settings"):new(settings.path):ui().series_style=="ribbon",
                "real entry must restore settings and finish the rollback journal")
        end
        print("KOReader real main Bootstrap failure recovery: OK "..failure);return
    end
    result=Bootstrap.load(options)
    if result.init then result.init(result) end
    if failure=="confirmed_retired" then
        assert(imports==1 and backend:validate(plugin,"0.5.0"),"retired backup cannot block a confirmed healthy startup")
    elseif failure=="tampered" then
        assert(not result.recovered and backend:validate(plugin,"0.5.0"),"modified recovery code must remain unexecuted")
    else
        assert(result.recovered and backend:validate(plugin,"0.4.1"))
        assert(require("koobone.settings"):new(settings.path):ui().series_style=="ribbon")
        if failure~="prepared" then
            local restored=assert(files:hash(settings.path))
            assert(not settings:flush() and files:hash(settings.path)==restored,
                "retained initialization settings/timers must not overwrite rollback settings")
        end
    end
    if failure=="prepared" or failure=="tampered" then assert(imports==0) end
    assert(package.path==original_path and package.loaded["koobone.update_files"]==original_backend,
        "recovery must not replace shared package paths or loaded modules")
end
print("KOReader verified startup module/init recovery: OK")
