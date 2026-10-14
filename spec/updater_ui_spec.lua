package.path="./koocomic.koplugin/?.lua;"..package.path
local shown,timers={},{}
for _,name in ipairs({"confirmbox","infomessage"}) do
    package.preload["ui/widget/"..name]=function() return {new=function(_,value) return value end} end
end
package.preload["ui/uimanager"]=function() return {show=function(_,value) shown[#shown+1]=value end,
    scheduleIn=function(_,_,callback) timers[#timers+1]=callback end,restartKOReader=function() end} end
package.preload["koobone.ui.download_dialog"]=function() return {new=function(_,value)
    value.show=function() end;value.close=function() end;value.setProgress=function() end;return value end} end
package.preload["socket"]=function() return {} end
local installed,rolled,changed=0,0,0
local processing={running=true,isActive=function() return false end}
local updater={current_version="0.4.1",canRollback=function() return true end,
    install=function() installed=installed+1;return true,"test sync warning" end,
    rollbackUpdate=function() rolled=rolled+1;return true end}
local ui=require("koobone.ui.updater"):new{updater=updater,preprocess=processing,
    downloader={isActive=function() return false end},on_changed=function() changed=changed+1 end}
ui:install{version="0.5.0"}
assert(#timers==0 and installed==0,"plugin installation must not run while preprocessing is active")
processing.running=false;ui:install{version="0.5.0"};processing.running=true
table.remove(timers,1)();assert(installed==0,"scheduled installation must recheck task activity")
processing.running=false;ui:install{version="0.5.0"};table.remove(timers,1)()
assert(installed==1 and changed==1 and shown[#shown].text:find("test sync warning",1,true),"successful installs must expose warnings and refresh lifecycle guards")
assert(type(ui.rollback)=="function","retained backup must be reachable through a confirmed native rollback action")
ui:rollback();assert(rolled==0 and shown[#shown].ok_callback)
shown[#shown].ok_callback();assert(rolled==1 and changed==2)
ui.downloader.service={queue={paused=false,jobs={{state="pending"}}}}
ui:install{version="0.5.0"}
assert(#timers==0,"an unpaused download waiting for its pump must block code replacement")
print("updater UI spec: OK")
