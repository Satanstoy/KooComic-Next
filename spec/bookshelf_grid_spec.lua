package.path = "./koocomic.koplugin/?.lua;./koocomic.koplugin/?/init.lua;" .. package.path

local function class()
    local object = {}
    function object:extend(fields)
        fields = fields or {}
        setmetatable(fields, { __index = self })
        return fields
    end
    function object:new(fields)
        fields = fields or {}
        setmetatable(fields, { __index = self })
        if fields.init then fields:init() end
        return fields
    end
    function object:getSize()
        return self.dimen or { w = self.width or 1, h = self.height or 1 }
    end
    function object:free() end
    function object:paintTo() end
    return object
end

local Widget = class()
local widget_modules = {
    "ui/widget/container/centercontainer",
    "ui/widget/container/framecontainer",
    "ui/widget/horizontalgroup",
    "ui/widget/horizontalspan",
    "ui/widget/iconwidget",
    "ui/widget/imagewidget",
    "ui/widget/overlapgroup",
    "ui/widget/textboxwidget",
    "ui/widget/textwidget",
    "ui/widget/verticalgroup",
    "ui/widget/verticalspan",
    "ui/widget/widget",
    "ui/widget/container/widgetcontainer",
}
for _, name in ipairs(widget_modules) do
    package.preload[name] = function() return Widget end
end
package.preload["ui/widget/container/inputcontainer"] = function() return Widget end
package.preload["ffi/blitbuffer"] = function()
    return {
        COLOR_WHITE = 255,
        COLOR_BLACK = 0,
        COLOR_DARK_GRAY = 64,
        COLOR_GRAY = 128,
        COLOR_GRAY_E = 224,
        gray = function(value) return math.floor((1-value)*255) end,
    }
end
package.preload["ffi"] = function() return {typeof=function() return "RGB32" end,istype=function() return false end} end
package.preload["ui/size"] = function() return {border={thin=1}} end
package.preload["device"] = function()
    return {
        hasKeys = function() return false end,
        input = { group = {} },
        screen = {
            getWidth = function() return 800 end,
            getHeight = function() return 1200 end,
            scaleBySize = function(_, value) return value end,
        },
    }
end
package.preload["ui/font"] = function()
    return { getFace = function(_,name,size) return {name=name,size=size} end }
end
package.preload["ui/geometry"] = function()
    return {
        new = function(_, value)
            value.copy = function(self)
                local result = {}
                for key, content in pairs(self) do result[key] = content end
                return result
            end
            return value
        end,
    }
end
package.preload["ui/gesturerange"] = function()
    return { new = function(_, value) return value end }
end

local shown
package.preload["ui/uimanager"] = function()
    return {
        show = function(_, widget)
            shown = widget
            if widget.onShow then widget:onShow() end
        end,
        close = function(_, widget)
            if widget.onCloseWidget then widget:onCloseWidget() end
        end,
        setDirty = function() end,
    }
end

local books = {}
for index = 1, 28 do
    books[index] = {
        vol_name = "Book " .. tostring(index),
        vol_author = "Author",
        count_page = 100,
        last_readpage = index,
    }
end
local storage = {
    isDownloaded = function(_, item) return item.vol_name == "Book 2" end,
    partSize = function() return 0 end,
}
local page_events = {}
local refresh_count = 0
local Grid = require("koobone.ui.bookshelf_grid")
local view = Grid.show{
    books = books,
    storage = storage,
    account = { nick = "Tester" },
    on_refresh = function() refresh_count = refresh_count + 1 end,
    on_page_changed = function(items, page, pages)
        page_events[#page_events + 1] = { count = #items, page = page, pages = pages }
    end,
}

assert(shown == view)
assert(view.perpage == 6)
assert(view.pages == 5)
assert(#view:visibleItems() == 6)
assert(page_events[1].page == 1 and page_events[1].pages == 5)

view:update{ ui = { portrait_columns = 2, portrait_rows = 2, text_size = "large" } }
assert(view.perpage == 2, "two wide covers cannot be squeezed into two short rows")
assert(view.pages == 14)
assert(#view:visibleItems() == 2)

view:update{ ui = { portrait_columns = 3, portrait_rows = 2, text_size = "large" } }
assert(view.perpage == 6)
assert(view.pages == 5)

view:_changePage(5)
assert(view.page == 5)
assert(#view:visibleItems() == 4)
assert(page_events[#page_events].page == 5)

view.options.row_key=function(item) return item.vol_name end
view:_changePage(2)
local old_first=view:visibleItems()[1]
local refreshed={}
for index=1,8 do refreshed[#refreshed+1]={vol_name="New "..index} end
for _,item in ipairs(books) do refreshed[#refreshed+1]={vol_name=item.vol_name} end
view:update{books=refreshed,preserve_anchor=true,page=2}
assert(view.page==3,"refresh insertion must preserve the old first identity, not just its page number")
local found=false
for _,item in ipairs(view:visibleItems()) do if item.vol_name==old_first.vol_name then found=true end end
assert(found,"stable refresh anchor must remain visible despite fresh table identities")
view:update{books=books,preserve_anchor=false,page=2}
assert(view.page==2,"ordinary navigation must not inherit refresh anchoring")
local rotation_first=view:visibleItems()[1].vol_name
view.options.ui={portrait_columns=2,portrait_rows=2}
view:onRotation()
assert(view:visibleItems()[1].vol_name==rotation_first,"layout reflow must preserve the visible identity")
view:update{ui={portrait_columns=3,portrait_rows=2},page=2,preserve_anchor=false}

view:update{ books = { books[1], books[2] } }
assert(view.page == 1)
assert(view.pages == 1)
assert(#view:visibleItems() == 2)

assert(view.layout and view.layout.header.h <= 52, "the old oversized header is still present")
assert(view.layout.footer.y + view.layout.footer.h == 1200)
assert(view.layout.footer.h <= 48, "pagination and commands must share a single footer")
assert(view.chrome.tabs[1].label == "系列" and view.chrome.tabs[2].label == "单卷")
assert(view.chrome.tabs[3].label == "已下载")
local series={vol_name="Original series/",_series={volume_count=19,downloaded_count=3}}
view:update{books={series},mode="series"}
local function find(widget,predicate,seen)
    if type(widget)~="table" then return end
    seen=seen or {};if seen[widget] then return end;seen[widget]=true
    if predicate(widget) then return widget end
    for _,child in pairs(widget) do
        local found=find(child,predicate,seen)
        if found then return found end
    end
end
assert(find(view,function(widget) return widget.text=="\195\151\226\128\13819" end),
    "the production series must use imported CountBadge glyph spacing")
assert(find(view,function(widget) return widget.text=="Original series/" and widget.alpha==true and widget.alignment=="left" end),
    "the production series must use imported FolderCard labels")
assert(find(view,function(widget) return widget.text=="\239\129\160" and widget.face.name=="symbols" end),
    "navigation must use a compact symbols-font back arrow, not the giant folded-up icon")
view:update{ui={series_style="ribbon"}}
assert(find(view,function(widget) return widget.text=="Original series/" and widget.alignment=="center" and widget.alpha==true end),
    "ribbon selection must change the actual series renderer")
view:update{ui={series_style="text"}}
local text_title=find(view,function(widget) return widget.text=="Original series/" end)
assert(text_title and text_title.height<=80,"text-only title must use a compact centered area away from corner badges")
view:update{books={books[1],books[2]},mode="volumes",selection_active=true,selected_count=1,
    is_selected=function(item) return item==books[1] end,on_hold=function() end,on_selection_cancel=function() end}
assert(view.chrome.selection==true,"multi-select must replace the actual footer, not add another bar")
assert(find(view,function(widget) return widget.text=="\239\128\140" end),"selected covers need a visible check glyph")
assert(find(view,function(widget) return widget.description=="删除本地" end),"selection footer must expose local delete")
assert(find(view,function(widget) return widget.description=="加入下载队列" end),"selection footer must expose a direct download command")
view:update{selected_count=0,on_selection_delete=function() error("empty selection deletion") end}
local empty_delete=find(view,function(widget) return widget.description=="删除本地" end)
assert(not empty_delete.callback,"disabled empty-selection delete must not retain a tap callback")
view:update{selection_delete_enabled=false,selection_action_icon="preprocess",status_for=function() return "处理中" end,
    tabs={{id="series",label="系列"},{id="volumes",label="单卷"},{id="downloaded",label="已处理"}}}
assert(view.chrome.tabs[3].label=="已处理" and find(view,function(widget) return widget.text=="处理中" end),
    "processing management must reuse grid chrome with domain-specific tabs and states")
assert(not find(view,function(widget) return widget.description=="删除本地" end) and
    find(view,function(widget) return widget.description=="去彩纹处理" end),"processing selection must not expose download/delete tools")
view:onBack()
assert(view.closed == true)
local returned=0
view=require("koobone.ui.bookshelf_grid").show{books=books,page=2,path_label="Series",
    storage=view.options.storage,
    on_back=function() returned=returned+1;return true end}
local page=view.page
assert(view:onShelfSwipe(nil,{direction="east",pos={x=1,y=200}}) and returned==1 and view.page==page,
    "left-edge right swipe must return without also turning a page")
assert(view:onShelfSwipe(nil,{direction="east",pos={x=400,y=200}}) and view.page==page-1 and returned==1,
    "content right swipe must page independently from edge return")
view:_close()

print("bookshelf grid spec: OK")
