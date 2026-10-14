require("setupkoenv")
local root=assert(arg[1]);package.path=root.."/koocomic.koplugin/?.lua;"..package.path
local width,height=assert(tonumber(arg[2])),assert(tonumber(arg[3]))
G_defaults=require("luadefaults"):open()
G_reader_settings=require("luasettings"):wrap{sdl_window={width=width,height=height},dev_no_c_blitter=false}
local Device=require("device");require("document/canvascontext"):init(Device)
local BB=require("ffi/blitbuffer")
local UI=require("ui/uimanager")
local lfs=require("libs/libkoreader-lfs")
local ffi=require("ffi")
local directory="/tmp/koocomic-ui-matrix-"..tonumber(ffi.C.getpid())
local files=require("koobone.preprocess_files"):new{roots={directory}};assert(files:mkdir(directory))
local cover_path=directory.."/same-cover.png"
local cover=BB.new(120,180,BB.TYPE_BBRGB32);cover:fill(BB.COLOR_WHITE)
cover:paintRectRGB32(8,8,104,72,BB.colorFromString("#38836c"))
cover:paintRectRGB32(8,88,104,84,BB.colorFromString("#c2446a"))
assert(cover:writeToFile(cover_path,"png"));cover:free()
local items={}
for index=1,40 do items[index]={file_md5=tostring(index),vol_name="长标题测试漫画 VeryLongOriginalComicNameWithoutSpaces Volume "..index,
    vol_series="长系列名称 Original Series",_koobone_cover_path=cover_path} end
local storage={isDownloaded=function(_,item) return tonumber(item.file_md5 or "0")%2==0 end,partSize=function() return 0 end}
local Grid=require("koobone.ui.bookshelf_grid")
local rendered_images
local function bounds(widget,seen)
    if type(widget)~="table" then return end
    seen=seen or {};if seen[widget] then return end;seen[widget]=true
    local rect=widget.dimen
    if rect and rect.x and rect.y and rect.w and rect.h and rect.w>0 and rect.h>0 then
        assert(rect.x>=-1 and rect.y>=-1 and rect.x+rect.w<=width+1 and rect.y+rect.h<=height+1,
            "rendered widget escaped viewport: "..tostring(widget.text or widget.description or "container"))
    end
    if widget.file==cover_path and widget._bb then rendered_images[#rendered_images+1]=widget end
    for _,child in ipairs(widget) do bounds(child,seen) end
    if widget.inner then bounds(widget.inner,seen) end
end
local function descriptors()
    local result={}
    for _,style in ipairs({"divider","ribbon","stack","collage","text","none"}) do
        result[#result+1]={name="series-"..style,mode="series",style=style,books={{vol_name=items[1].vol_series,
            _series={books=items,volume_count=40,downloaded_count=20}}}}
    end
    for _,name in ipairs({"volumes","inside-series","search","selected","empty","loading","error"}) do
        result[#result+1]={name=name,mode="volumes",books=name=="empty" and {} or items}
    end
    return result
end
local cases=0
for _,font in ipairs({"normal","large"}) do
    for _,format in ipairs({{name="gray",kind=BB.TYPE_BB8},{name="rgb",kind=BB.TYPE_BBRGB32}}) do
        for _,night in ipairs({false,true}) do
            Device.screen.night_mode=night
            for _,state in ipairs(descriptors()) do
                local shelf=Grid.show{books=state.books,mode=state.mode,storage=storage,row_key=function(item) return item.file_md5 end,
                    ui={text_size=font,series_style=state.style or "divider"},
                    path_label=(state.name=="inside-series" or state.name=="search") and "长系列名称 VeryLongOriginalComicNameWithoutSpaces / 搜索" or nil,
                    selection_active=state.name=="selected",selected_count=40,is_selected=function() return state.name=="selected" end}
                local canvas=BB.new(width,height,format.kind);canvas:fill(BB.COLOR_WHITE)
                rendered_images={}
                shelf:paintTo(canvas,0,0);bounds(shelf)
                if state.name=="loading" or state.name=="error" then
                    local message=require("ui/widget/infomessage"):new{text=state.name=="loading" and "正在刷新书架……" or "生成离线错误：无法刷新书架。"}
                    UI:show(message);message:paintTo(canvas,0,0);bounds(message);UI:close(message)
                end
                local ink=0
                for y=0,height-1,12 do for x=0,width-1,12 do if canvas:getPixel(x,y):getColor8().a<240 then ink=ink+1 end end end
                assert(ink>30,"native matrix frame must not be blank: "..state.name)
                if night then canvas:invert() end
                local name=font.."-"..format.name.."-"..(night and "night" or "day").."-"..state.name
                assert(canvas:writeToFile(directory.."/"..name..".png","png"))
                shelf:_close();canvas:free()
                for _,image in ipairs(rendered_images) do assert(image._bb==nil,"native cover buffers must release on close") end
                assert(shelf.closed and #UI._window_stack==0,"closing each frame must release native window references")
                cases=cases+1
            end
        end
    end
end
local function descriptors_open()
    local count=0;for name in lfs.dir("/proc/self/fd") do if name~="." and name~=".." then count=count+1 end end;return count
end
collectgarbage("collect");local before=descriptors_open()
for _=1,16 do
    local shelf=Grid.show{books=items,mode="volumes",storage=storage,ui={text_size="large"}}
    local canvas=BB.new(width,height,BB.TYPE_BBRGB32);shelf:paintTo(canvas,0,0);shelf:_close();canvas:free()
end
collectgarbage("collect")
assert(descriptors_open()==before,"repeated warmed native views must not leak file descriptors")
Device.screen.night_mode=false
Device:exit()
print("KOReader native UI matrix: OK "..width.."x"..height.." frames="..cases.." "..directory)
