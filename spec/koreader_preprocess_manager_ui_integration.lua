require("setupkoenv")
local root=assert(arg[1]);package.path=root.."/koocomic.koplugin/?.lua;"..package.path
local width,height=tonumber(arg[2]) or 600,tonumber(arg[3]) or 800
G_defaults=require("luadefaults"):open()
G_reader_settings=require("luasettings"):wrap{sdl_window={width=width,height=height},dev_no_c_blitter=false}
local Device=require("device")
require("document/canvascontext"):init(Device)
local UI=require("ui/uimanager")
local BB=require("ffi/blitbuffer")
local ffi=require("ffi")
local directory="/tmp/koocomic-manager-ui-"..tonumber(ffi.C.getpid())
local files=require("koobone.preprocess_files"):new{roots={directory}};assert(files:mkdir(directory))
local cover_path=directory.."/generated-cover.png"
local cover=BB.new(120,180,BB.TYPE_BBRGB32);cover:fill(BB.COLOR_WHITE)
for row=0,4 do cover:paintRect(8,8+row*32,104,24,BB.gray(0.2+row*0.1)) end
assert(cover:writeToFile(cover_path,"png"));cover:free()
local records,items={},{}
for index=1,9 do
    local key="generated-"..index
    local path=directory.."/"..key..".epub"
    assert(files:write(path,"generated UI-only file fixture"))
    records[key]={path=path,title="测试漫画 "..index,state="complete",updated_at=index}
    items[#items+1]={file_md5=key,vol_name=records[key].title,vol_series="测试系列",vol_author="Fixture"}
end
local settings={data={preprocess={strength=0.8,scale_mode="original"}},
    download=function() return {directory=directory,records=records} end,flush=function() return true end,
    ui=function() return {portrait_columns=3,portrait_rows=2,landscape_columns=4,landscape_rows=2,series_style="divider",text_size="large"} end}
local storage=require("koobone.storage"):new(settings)
local status_tasks={}
local service={available=true,running=false,files=files,isActive=function() return false end,
    jobs=function() return {{id="optimized",state="completed",source_path=records["generated-1"].path,profile={},
        output_fingerprint=files:hash(records["generated-1"].path)},
        {id="failed",state="failed",source_path=records["generated-2"].path},
        {id="waiting",state="pending",source_path=records["generated-3"].path}} end,
    isLocked=function(_,path) return path==records["generated-4"].path end,
    previewBatch=function(_,selected) return {files=#selected,bytes=40,temporary_bytes=40,duplicate=0,occupied=0,invalid=0,
        profile={strength=0.8,scale_mode="original",discard_original=true}} end}
local manager=require("koobone.ui.preprocess_manager"):new{storage=storage,service=service,settings=settings,library={items=items},
    status_schedule=function(_,callback) status_tasks[#status_tasks+1]=callback end,
    cover_cache={localPath=function() return cover_path end}}
manager.shelf.navigation:switch("volumes")
local view=manager:show()
while #status_tasks>0 do table.remove(status_tasks,1)() end
local optimized_item
for _,item in ipairs(manager.shelf.library.items) do if item.file_md5=="generated-1" then optimized_item=item end end
assert(optimized_item and manager:state(optimized_item)=="optimized","native async fingerprint verification must resolve the current file")
service.running=true
view.options.on_hold(view:visibleItems()[1])
assert(view.chrome.selection and view.chrome.tabs[3].label=="已处理")
local function find(widget,predicate,seen)
    if type(widget)~="table" then return end
    seen=seen or {};if seen[widget] then return end;seen[widget]=true
    if predicate(widget) then return widget end
    for _,child in pairs(widget) do local found=find(child,predicate,seen);if found then return found end end
end
assert(find(view,function(widget) return widget.file==cover_path end),"actual cached bitmap must render, not a fallback placeholder")
assert(find(view,function(widget) return widget.description=="去彩纹处理" end) and
    not find(view,function(widget) return widget.description=="删除本地" end))
local canvas=BB.new(width,height,BB.TYPE_BBRGB32);canvas:fill(BB.COLOR_WHITE)
view:paintTo(canvas,0,0)
local ink=0
for y=60,height-60,10 do for x=10,width-10,10 do if canvas:getPixel(x,y):getColor8().a<240 then ink=ink+1 end end end
assert(ink>100,"actual processing grid must be nonblank")
assert(canvas:writeToFile(directory.."/management.png","png"))
view.options.on_selection_download()
local confirm=UI._window_stack[#UI._window_stack].widget
assert(confirm.ok_callback and confirm.text:find("不保留原版备份",1,true))
UI:close(confirm);UI:close(view);canvas:free()
assert(not manager.watch and not manager.watched_view and manager.shelf.menu==nil and service.running,
    "native close must release UI references without cancelling processing")
local queue_service={available=true,running=true,jobs=function() return {} end,pause=function(self) self.running=false;return true end}
local queue=require("koobone.ui.preprocess").show(storage,queue_service,{queue_only=true})
queue:onMenuSelect(queue.item_table[1])
assert(not queue_service.running)
UI:close(queue)
print("KOReader processing management UI: OK "..width.."x"..height.." "..directory.."/management.png")
Device:exit()
