package.path="./koocomic.koplugin/?.lua;"..package.path
local function widget() return {new=function(_,fields) return fields end} end
for _,module in ipairs({"buttondialog","infomessage","menu","multiinputdialog","confirmbox"}) do package.preload["ui/widget/"..module]=widget end
package.preload["socket"]=function() return {gettime=os.time} end
local shown,current,renders=nil,nil,0
local timers={}
package.preload["ui/uimanager"]=function() return {show=function(_,value) shown=value end,close=function() end,
    scheduleIn=function(_,_,callback) timers[#timers+1]=callback end,
    unschedule=function(_,callback) for index=#timers,1,-1 do if timers[index]==callback then table.remove(timers,index) end end end} end
package.preload["koobone.ui.book_detail"]=function() return {show=function() error("processing view must not open download details") end} end
package.preload["koobone.ui.bookshelf_grid"]=function() return {show=function(options)
    current=options;return {closed=false,options=options,
        update=function(self,value) for key,item in pairs(value) do self.options[key]=item end;current=value;renders=renders+1 end,
        onCloseWidget=function(self) self.closed=true;if self.options.on_close then self.options.on_close() end end}
end} end
local loaded,Manager=pcall(require,"koobone.ui.preprocess_manager")
assert(loaded,"processing management must reuse the real Bookshelf controller and grid")
local records={{key="one",value={title="Original 1",path="/books/one.epub"}},{key="two",value={title="Original 2",path="/books/two.epub"}}}
local storage={records=function() return records end,recordInfo=function(_,row) return {exists=true,path=row.value.path,title=row.value.title} end,
    itemKey=function(_,item) return item.file_md5 end,resolveLocalPath=function(_,item) return "/books/"..item.file_md5..".epub" end}
local queued
local listener
local service={available=true,running=true,isActive=function() return false end,record=function() end,jobs=function() return {} end,isLocked=function() return false end,
    subscribe=function(_,callback) listener=callback;return function() listener=nil end end,
    profile=function() return {strength=0.8,scale_mode="original",discard_original=true} end,
    previewBatch=function(_,items) return {files=#items,bytes=20,temporary_bytes=20,duplicate=0,occupied=0,invalid=0,
        profile={strength=0.8,scale_mode="original",discard_original=true}} end,
    submitBatch=function(_,items) queued=items;return {added=#items} end,resume=function() return true end}
local manager=Manager:new{storage=storage,service=service,settings={data={preprocess={strength=0.8}},ui=function() return {} end},
    library={items={{file_md5="one",vol_name="Original 1",vol_series="Series",vol_author="Author"},
        {file_md5="two",vol_name="Original 2",vol_series="Series",vol_author="Author"}}}}
manager:show()
assert(current.tabs[3].label=="已处理" and current.status_for and current.selection_action_icon=="preprocess")
current.on_select(current.books[1]);assert(#current.books==2)
current.on_hold(current.books[1]);current.on_select(current.books[2])
assert(current.selected_count==2 and current.selection_delete_enabled==false)
current.on_selection_download();assert(shown.ok_callback and shown.text:find("不保留原版备份",1,true) and not queued)
shown.ok_callback();assert(#queued==2 and queued[1].vol_name=="Original 1")
manager:showFilter();assert(shown.buttons[1][1].text=="全部")
shown.buttons[4][1].callback()
assert(current.selected_count==2,"state filtering must retain cross-page selected IDs")
assert(#timers>0,"visible processing management must refresh when background job states change")
local before=renders
service.running=false
service.jobs=function() return {{id="failed",state="failed",source_path="/books/one.epub"}} end
table.remove(timers,1)()
assert(renders>before and #timers==0,"state change must repaint once, then stop polling an idle manager")
service.running=true;listener()
assert(#timers==1,"resuming through a queue overlay must restart the idle manager watch")
service.running=false;table.remove(timers,1)()
local reads=0
service.jobs=function() reads=reads+1;return {} end
manager:show()
for _=1,100 do manager:state(manager.shelf.library.items[1]) end
assert(reads<=2,"series counters must use one indexed job snapshot, not rescan the queue for each book")
manager.shelf.grid_view:onCloseWidget()
assert(not manager.watch and not manager.watched_view and manager.shelf.menu==nil and #manager.shelf.library.items==0 and #timers==0,
    "closing management must release the timer, grid and copied local catalog without cancelling background processing")
assert(listener==nil,"closing management must unsubscribe persistence events")
manager.filter="all"
manager.source_library.items[2].vol_series="Other"
manager:show();current.on_select(current.books[1])
manager:showActions();shown.buttons[1][1].callback();shown.ok_callback()
assert(#queued==1 and queued[1].file_md5=="one","processing current results must stay within the entered series")
current.on_back()
local version,hash=1,string.rep("a",64)
storage.fileIdentity=function() return version end
service.files={hashAsync=function(_,_,schedule,guard,done) schedule(0,function() done(guard() and hash or nil) end) end}
service.jobs=function() return {{id="optimized",source_path="/books/one.epub",state="completed",profile={},output_fingerprint=string.rep("a",64)}} end
manager:show();assert(manager:state(manager.shelf.library.items[1])=="checking","completed files must be verified before showing optimized")
while #timers>0 do table.remove(timers,1)() end
manager.shelf.navigation:switch("downloaded");manager:show()
manager:showActions();shown.buttons[1][1].callback();shown.ok_callback()
assert(#queued==1 and queued[1].file_md5=="one","processed-tab actions must not include hidden unprocessed volumes")
version=2;hash=string.rep("b",64)
assert(manager:state(manager.shelf.library.items[1])=="checking")
while #timers>0 do table.remove(timers,1)() end
assert(manager:state(manager.shelf.library.items[1])=="unprocessed","same-path redownload must invalidate historical success")
storage.resolveLocalPath=function() return nil end
assert(manager:state(manager.shelf.library.items[1])=="missing","cached paths must not conceal deleted files")
print("preprocess manager spec: OK")
