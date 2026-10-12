package.path="./koocomic.koplugin/?.lua;"..package.path
local function class()
    local object={}
    function object:extend(fields) return setmetatable(fields or {},{__index=self}) end
    function object:new(fields)
        local value=setmetatable(fields or {},{__index=self})
        if value.init then value:init() end
        return value
    end
    function object:getSize()
        if self.text then
            local lines=math.max(1,math.ceil(#self.text/math.max(1,math.floor(self.width/8))))
            return {w=self.width,h=self.height or lines*20}
        end
        return self.dimen or {w=self.width or 0,h=self.height or 0}
    end
    function object:free() end
    return object
end
local Widget=class()
for _,name in ipairs({"ui/widget/container/framecontainer","ui/widget/widget","ui/widget/textwidget","ui/widget/textboxwidget"}) do
    package.preload[name]=function() return Widget end
end
package.preload["ui/geometry"]=function() return {new=function(_,value) return value end} end
package.preload["ui/font"]=function() return {getFace=function(_,name,size) return {name=name,size=size} end} end
package.preload["ui/size"]=function() return {border={thin=1}} end
package.preload["ffi/blitbuffer"]=function() return {COLOR_BLACK=0,COLOR_WHITE=255} end
package.preload["device"]=function() return {screen={getWidth=function() return 600 end,
    getHeight=function() return 800 end,scaleBySize=function(_,n) return n end}} end
local badge_ok,Badge=pcall(require,"koobone.ui.vendor.bookshelf.count_badge")
assert(badge_ok,"the production UI must import the upstream CountBadge renderer")
local folder_ok,Folder=pcall(require,"koobone.ui.vendor.bookshelf.folder_card")
assert(folder_ok,"the production UI must import the upstream FolderCard renderer")
local theme={badge_bg=255,badge_fg=0,folder_bg=180,folder_fg=0,border=0}
local face={size=16}
local badge=Badge.render(19,{theme=theme,face=face})
assert(badge.background==255 and badge.color==0 and badge.radius>0)
assert(badge[1].text=="\195\151\226\128\13819","upstream multiplication/hair-space glyphs must be preserved")
assert(badge[1].face==face and badge.padding_left>0 and badge.padding_top>0)
assert(Badge.render(0,{theme=theme})==nil)
local folder,label,floor=Folder.build{width=180,height=250,label="Original series/",theme=theme,face=face}
assert(folder[1].width==180-Folder.SHADOW_OFFSET)
assert(folder[1].fill_color==180 and folder[1].edge_color==0)
assert(label[1].text=="Original series/","series names are not filesystem names and must stay unchanged")
assert(label[1].alignment=="left" and label[1].face==face and label[1].alpha==true)
assert(folder[1].tab_w==math.floor(folder[1].width*0.4))
assert(folder[1].tab_h==10,"the tab must be derived from actual font line height")
assert(label[1].height<=40 and floor>0 and floor<250)
local _,long=Folder.build{width=180,height=250,label=string.rep("Long series ",30),theme=theme,face=face}
assert(long[1].height==40 and long[1].height_overflow_show_ellipsis==true)
for name in pairs(package.loaded) do assert(not name:match("^lib/bookshelf_"),"upstream singleton leaked: "..name) end
print("Bookshelf imported components spec: OK")
