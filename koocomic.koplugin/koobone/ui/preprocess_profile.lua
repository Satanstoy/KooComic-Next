-- SPDX-License-Identifier: AGPL-3.0-only
local Menu=require("ui/widget/menu")
local Spin=require("ui/widget/spinwidget")
local Info=require("ui/widget/infomessage")
local UI=require("ui/uimanager")
local Profile=require("koobone.preprocess_profile")
local View={}
function View.show(settings,on_changed)
    local profile,err=Profile.normalize(settings.data.preprocess)
    if not profile then UI:show(Info:new{text=tostring(err)});return end
    local menu
    local function apply(values)
        local validated,error_message=Profile.normalize(values)
        if not validated then UI:show(Info:new{text=tostring(error_message)});return end
        local previous=settings.data.preprocess
        settings.data.preprocess=validated
        local ok,saved=pcall(settings.flush,settings)
        if not ok or saved==false then
            settings.data.preprocess=previous
            UI:show(Info:new{text="处理参数未能保存"});return
        end
        UI:close(menu)
        if on_changed then on_changed() end
        View.show(settings,on_changed)
    end
    local function numeric(field,title,minimum,maximum,step)
        UI:show(Spin:new{title_text=title,value=field=="strength" and math.floor(profile.strength*100+0.5) or profile[field],
            value_min=minimum,value_max=maximum,value_step=step,value_hold_step=step*5,
            callback=function(widget)
                local values={};for key,value in pairs(profile) do values[key]=value end
                values[field]=field=="strength" and widget.value/100 or widget.value
                apply(values)
            end})
    end
    local rows={
        {text="处理尺度",mandatory=profile.scale_mode=="original" and "原尺寸" or "目标尺寸",callback=function()
            local picker
            local items={}
            for _,mode in ipairs({{id="original",text="原尺寸"},{id="fit",text="目标尺寸"}}) do
                local id=mode.id
                items[#items+1]={text=mode.text,checked=profile.scale_mode==id,callback=function()
                    local values={strength=profile.strength,scale_mode=id}
                    if id=="fit" then
                        local screen=require("device").screen
                        values.target_width=profile.target_width or screen:getWidth()
                        values.target_height=profile.target_height or screen:getHeight()
                    end
                    UI:close(picker);apply(values)
                end}
            end
            picker=Menu:new{title="处理尺度",item_table=items,is_borderless=true,title_bar_fm_style=true};UI:show(picker)
        end},
        {text="去彩纹强度",mandatory=tostring(math.floor(profile.strength*100+0.5)).."%",callback=function()
            numeric("strength","去彩纹强度 (%)",0,100,5)
        end},
    }
    if profile.scale_mode=="fit" then
        rows[#rows+1]={text="目标宽度",mandatory=tostring(profile.target_width),callback=function() numeric("target_width","目标宽度 (px)",1,16384,8) end}
        rows[#rows+1]={text="目标高度",mandatory=tostring(profile.target_height),callback=function() numeric("target_height","目标高度 (px)",1,16384,8) end}
    end
    menu=Menu:new{title="去彩纹参数",item_table=rows,is_borderless=true,title_bar_fm_style=true}
    UI:show(menu);return menu
end
return View
