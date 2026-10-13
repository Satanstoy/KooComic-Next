-- SPDX-License-Identifier: AGPL-3.0-only
local Bootstrap=require("koobone.update_bootstrap")
local directory=assert(debug.getinfo(1,"S").source:match("^@(.+)/main%.lua$"))
return Bootstrap.load{
    plugin_dir=directory,
    settings_path=require("datastorage"):getSettingsDir().."/koocomic.lua",
    loader=function() return require("koobone.plugin") end,
    fallback=function(recovered)
        local UI=require("ui/uimanager")
        local Info=require("ui/widget/infomessage")
        local Widget=require("ui/widget/container/widgetcontainer")
        local fallback=Widget:extend{name="koocomic",is_doc_only=false,restart_required=true}
        local message=recovered and "更新启动失败，已恢复旧插件和设置，请重启 KOReader。" or
            "更新恢复未完成，备份已保留。请重启 KOReader；恢复前暂停漫画操作。"
        function fallback:init()
            UI:show(Info:new{text=message})
            if self.ui and self.ui.menu then self.ui.menu:registerToMainMenu(self) end
        end
        function fallback:addToMainMenu(menu)
            menu.koocomic={text="koo漫画：需要重启",callback=function() UI:restartKOReader() end}
        end
        return fallback
    end,
}
