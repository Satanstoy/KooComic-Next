-- SPDX-License-Identifier: AGPL-3.0-only
local Menu=require("ui/widget/menu")
local ButtonDialog=require("ui/widget/buttondialog")
local ConfirmBox=require("ui/widget/confirmbox")
local InfoMessage=require("ui/widget/infomessage")
local UIManager=require("ui/uimanager")
local PreprocessUI={}
local names={pending="等待",preparing="校验源文件",processing="处理中",validating="校验结果",
    completed="完成",failed="失败",cancelled="已取消"}

local function report(ok,err)
    if not ok then UIManager:show(InfoMessage:new{text=tostring(err or "操作失败")}) end
end

function PreprocessUI.show(storage,service)
    if not service.available then
        UIManager:show(InfoMessage:new{text="去彩纹处理不可用：\n"..tostring(service.reason)})
        return
    end
    local menu,closed=false,false
    local function localBooks()
        local items={}
        for _, row in ipairs(storage:records()) do
            local info=storage:recordInfo(row)
            if info and info.exists then
                local item={file_md5=row.key,vol_name=info.title}
                items[#items+1]={text=info.title,mandatory=service:record(info.path) and "已优化" or "未处理",
                    callback=function()
                        local dialog
                        local function action(restore)
                            UIManager:close(dialog)
                            UIManager:show(ConfirmBox:new{text=(restore and "恢复原版？" or "处理这本本地漫画的彩纹？").."\n\n"..info.title,
                                ok_text=restore and "恢复原版" or "开始处理",ok_callback=function()
                                    local ok,err
                                    if restore then ok,err=service:restore(item) else ok,err=service:submit(item) end
                                    report(ok,err)
                                    if ok then report(service:resume()) end
                                end})
                        end
                        dialog=ButtonDialog:new{title=info.title,buttons={
                            {{text="去彩纹处理",callback=function() action(false) end}},
                            {{text="恢复原版",enabled=service:record(info.path)~=nil,callback=function() action(true) end}},
                            {{text="关闭",callback=function() UIManager:close(dialog) end}},
                        }}
                        UIManager:show(dialog)
                    end}
            end
        end
        UIManager:show(Menu:new{title="本地漫画",item_table=items,is_borderless=true,title_bar_fm_style=true})
    end
    local function rows()
        local result={
            {text=service.running and "暂停队列" or "继续队列",callback=function()
                if service.running then report(service:pause()) else report(service:resume()) end
            end},
            {text="本地漫画",callback=localBooks},
            {text="重新核对文件事务",callback=function() service:reconcile() end},
        }
        for _, job in ipairs(service:jobs()) do
            local value=job
            local title=value.source_path:match("([^/]+)$") or value.book_id
            result[#result+1]={text=title,mandatory=names[value.state] or value.state,
                post_text=value.total_pages and (tostring(value.processed_pages or 0).." / "..value.total_pages) or nil,
                callback=function()
                    local dialog
                    dialog=ButtonDialog:new{title=title,buttons={
                        {{text="取消任务",enabled=value.state=="pending" or value.state=="preparing" or value.state=="processing" or value.state=="validating",
                            callback=function() report(service:cancel(value.id));UIManager:close(dialog) end}},
                        {{text="重试",enabled=value.state=="failed" or value.state=="cancelled",
                            callback=function() local ok,err=service:retry(value.id);report(ok,err);if ok then report(service:resume()) end;UIManager:close(dialog) end}},
                        {{text="查看错误",enabled=value.error~=nil,callback=function()
                            UIManager:show(InfoMessage:new{text=tostring(value.error or "无错误")})
                        end}},
                        {{text="关闭",callback=function() UIManager:close(dialog) end}},
                    }}
                    UIManager:show(dialog)
                end}
        end
        return result
    end
    menu=Menu:new{title="图像优化 / 去彩纹管理",item_table=rows(),is_borderless=true,title_bar_fm_style=true,
        close_callback=function() closed=true end}
    UIManager:show(menu)
    local function update()
        if closed then return end
        menu.item_table=rows()
        if menu.updateItems then menu:updateItems(nil,true) end
        UIManager:setDirty(menu,"ui")
        UIManager:scheduleIn(1,update)
    end
    UIManager:scheduleIn(1,update)
    return menu
end

return PreprocessUI
