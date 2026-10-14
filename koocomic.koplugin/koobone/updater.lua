local Archiver = require("ffi/archiver")
local JSON = require("json")
local lfs = require("libs/libkoreader-lfs")
local Util = require("koobone.util")
local Version = require("version")
local Guard=require("koobone.runtime_guard")

local Updater = {}
Updater.__index = Updater

Updater.MAX_MANIFEST_BYTES = 128 * 1024
Updater.MAX_PACKAGE_BYTES = 15 * 1024 * 1024

local function pluginDirFromSource()
    local source = debug.getinfo(1, "S").source or ""
    return source:match("^@?(.+)/koobone/updater%.lua$")
end

local function normalizeNotes(notes)
    if type(notes) == "table" then
        local rows = {}
        for _, value in ipairs(notes) do
            local row = Util.cleanMessage(value, 240)
            if row ~= "" then rows[#rows + 1] = "• " .. row end
        end
        notes = table.concat(rows, "\n")
    end
    notes = tostring(notes or "")
    if #notes > 1800 then notes = notes:sub(1, 1797) .. "..." end
    return notes
end

function Updater:new(options)
    options = options or {}
    return setmetatable({
        settings = assert(options.settings, "settings required"),
        api = assert(options.api, "api required"),
        current_version = assert(options.current_version, "current version required"),
        manifest_url = options.manifest_url or "",
        release_prefix = options.release_prefix or "",
        plugin_dir = options.plugin_dir or pluginDirFromSource(),
        workloads=options.workloads or {},
    }, self)
end

function Updater:isConfigured()
    return self.manifest_url:match("^https://") ~= nil
        and self.release_prefix:match("^https://") ~= nil
end

function Updater:_manifestUrlAllowed(url)
    return self:isConfigured() and url == self.manifest_url
end

function Updater:_packageUrlAllowed(url)
    return self:isConfigured() and type(url) == "string"
        and url:sub(1, #self.release_prefix) == self.release_prefix
        and url:sub(#self.release_prefix+1):match("^v%d+%.%d+%.%d+/[%w_.%-]+%.zip$")~=nil
end

function Updater:_validateManifest(data)
    if type(data) ~= "table" then return nil, "更新清单格式无效" end
    if data.product_id~="koocomic-next" then return nil,"更新清单不属于 KooComic Next" end
    local version = tostring(data.version or "")
    if not Util.compareVersions(version, version) then return nil, "版本号格式无效" end
    if data.channel ~= nil and data.channel ~= "stable" then return nil, "不是正式版更新" end
    if data.package_type ~= nil and data.package_type ~= "full" then
        return nil, "只支持完整更新包"
    end
    local package_url = data.package_url
    if not self:_packageUrlAllowed(package_url) then return nil, "更新包地址不在允许范围内" end
    local size = tonumber(data.size)
    if not size or size~=size or size <= 0 or size > self.MAX_PACKAGE_BYTES or size~=math.floor(size) then
        return nil, "更新包大小无效"
    end
    local sha256 = tostring(data.sha256 or ""):lower():gsub("%s+", "")
    if not sha256:match("^[0-9a-f]+$") or #sha256 ~= 64 then
        return nil, "更新包缺少有效 SHA-256"
    end
    return {
        product_id = "koocomic-next",
        version = version,
        package_url = package_url,
        size = size,
        sha256 = sha256,
        summary = Util.cleanMessage(data.summary, 320),
        notes = normalizeNotes(data.notes),
        published_at = Util.cleanMessage(data.published_at, 40),
        min_koreader = Util.cleanMessage(data.min_koreader, 40),
    }
end

function Updater:check()
    local active,reason=Guard.ensure();if not active then return nil,reason end
    if not self:isConfigured() then return nil, "not_configured" end
    if not self:_manifestUrlAllowed(self.manifest_url) then return nil, "更新清单地址无效" end
    local response, err = self.api:requestOk{
        url = self.manifest_url,
        method = "GET",
        include_session = false,
        redirect = true,
        headers = {
            ["Accept"] = "application/json",
            ["User-Agent"] = "kooComic-KOReader-Updater/0.4.1",
        },
        block_timeout = 15,
        total_timeout = 30,
    }
    if not response then return nil, err end
    if #(response.body or "") > self.MAX_MANIFEST_BYTES then
        return nil, "更新清单过大"
    end
    local ok, decoded = pcall(JSON.decode, response.body or "")
    if not ok then return nil, "无法解析更新清单" end
    local release, validate_err = self:_validateManifest(decoded)
    if not release then return nil, validate_err end

    local state = self.settings:update()
    state.last_auto_update_check_at = os.time()
    state.last_seen_update_version = release.version
    if Util.compareVersions(release.version, self.current_version) == 1 then
        state.available = release
    else
        state.available = nil
    end
    self.settings:flush()
    return release, Util.compareVersions(release.version, self.current_version) == 1
end

function Updater:shouldAutoCheck()
    if not Guard.ensure() then return false end
    local state = self.settings:update()
    if not self:isConfigured() or state.auto_check_enabled ~= true then return false end
    if state.auto_update_prompt_disabled == true then return false end
    return Util.localDate(state.last_auto_update_check_at) ~= Util.localDate()
end

function Updater:shouldPrompt(release)
    local state = self.settings:update()
    if not release or Util.compareVersions(release.version, self.current_version) ~= 1 then return false end
    if state.auto_update_prompt_disabled == true then return false end
    if tonumber(state.update_prompt_later_count or 0) >= 3 then return false end
    return state.last_update_prompt_date ~= Util.localDate()
end

function Updater:markPromptShown(release)
    if not Guard.ensure() then return false end
    local state = self.settings:update()
    state.last_update_prompt_date = Util.localDate()
    state.last_seen_update_version = release and release.version or state.last_seen_update_version
    self.settings:flush()
end

function Updater:deferPrompt()
    if not Guard.ensure() then return false end
    local state = self.settings:update()
    state.update_prompt_later_count = math.min(3,
        tonumber(state.update_prompt_later_count or 0) + 1)
    if state.update_prompt_later_count >= 3 then
        state.auto_update_prompt_disabled = true
        state.auto_check_enabled = false
    end
    self.settings:flush()
end

function Updater:resetPromptPolicy()
    if not Guard.ensure() then return false end
    local state = self.settings:update()
    state.update_prompt_later_count = 0
    state.auto_update_prompt_disabled = false
    state.last_update_prompt_date = ""
    state.auto_check_enabled = true
    self.settings:flush()
end

function Updater:_extractPackage(archive_path, stage_path)
    local files=require("koobone.preprocess_files"):new{roots={stage_path}}
    local reader=Archiver.Reader:new()
    return require("koobone.update_package"):new{reader=reader,files=files}:extract(archive_path,stage_path)
end

function Updater:_transaction()
    if self.transaction then return self.transaction end
    local called,backend=pcall(function()
        return require("koobone.update_files"):new{plugin_dir=self.plugin_dir,settings=self.settings}
    end)
    if not called then return nil,"更新文件能力不可用" end
    self.backend=backend
    self.transaction=require("koobone.update_transaction"):new{backend=backend,paths=backend.paths}
    self.staging=require("koobone.update_staging"):new{backend=backend}
    return self.transaction
end

function Updater:recoverUpdate()
    local tx,err=self:_transaction();if not tx then return nil,err end
    local record,read_error=self.backend:load()
    if read_error then return nil,read_error end
    if record then
        local prior=self.backend:identity(self.backend.paths.live)
        local ok,recovery_error=tx:recover(self.current_version)
        self.restart_required=self.backend:identity(self.backend.paths.live)~=prior or
            not self.backend:validate(self.backend.paths.live,self.current_version)
        if self.restart_required then Guard.block() end
        if not ok then return nil,recovery_error end
    end
    return self.staging:cleanup()
end

function Updater:canRollback()
    local tx=self:_transaction();if not tx then return false end
    local record=tx:_load()
    return record and (record.phase=="installed" or record.phase=="confirmed") and
        self.backend:identity(self.backend.paths.live)==record.new_identity and
        self.backend:identity(self.backend.paths.backup)==record.old_identity and
        self.backend:identity(self.backend.paths.config)==record.config_identity or false
end

function Updater:rollbackUpdate()
    local tx,err=self:_transaction();if not tx then return nil,err end
    local prior=self.backend:identity(self.backend.paths.live)
    local ok,rollback_error=tx:rollback()
    self.restart_required=self.backend:identity(self.backend.paths.live)~=prior or
        not self.backend:validate(self.backend.paths.live,self.current_version)
    if self.restart_required then Guard.block() end
    return ok,rollback_error
end

function Updater:install(release, on_progress)
    local active,reason=Guard.ensure();if not active then return nil,reason end
    local validated=self:_validateManifest(release)
    if not validated or Util.compareVersions(validated.version,self.current_version)~=1 then
        return nil, "更新信息无效"
    end
    release=validated
    if Guard.busy(self.workloads) then return nil,"下载或去彩纹任务正在运行" end
    local tx,transaction_error=self:_transaction();if not tx then return nil,transaction_error end
    if self.busy then return nil,"插件更新正在进行" end
    if self.restart_required and not self.backend:validate(self.backend.paths.live,self.current_version) then
        return nil,"请先重启 KOReader" end
    local recovered,recovery_error=self:recoverUpdate();if not recovered then return nil,recovery_error end
    if self.restart_required then return nil,"已恢复旧代码，请先重启 KOReader" end
    local retired,retire_error=tx:prepareNew();if not retired then return nil,retire_error end
    local began,begin_error=self.staging:begin();if not began then return nil,begin_error end
    self.busy=true
    local function fail(message)
        self.busy=false
        local restored,restore_error=self:recoverUpdate()
        return nil,restored and tostring(message) or tostring(message).."；恢复待处理："..tostring(restore_error)
    end
    local made,work_error=self.staging:createWork();if not made then return fail(work_error) end
    local handle,open_error=self.staging:openArchive();if not handle then return fail(open_error) end
    local archive,stage=self.backend.paths.archive,self.backend.paths.work
    local archive_identity=self.backend:identity(archive)
    local function report(stage, percent, current, total)
        if on_progress then
            pcall(on_progress,{
                stage = stage,
                percent = percent,
                current = current or 0,
                total = total or 0,
            })
        end
    end

    report("正在下载更新包", 2, 0, release.size)
    local called,ok,err=pcall(self.api.download,self.api,release.package_url,archive,{
        handle=handle,
        total = release.size,
        max_bytes = self.MAX_PACKAGE_BYTES,
        headers = {
            ["Accept"] = "application/zip, application/octet-stream",
            ["User-Agent"] = "kooComic-KOReader-Updater/0.4.1",
        },
        on_progress = function(current, total)
            local ratio = total > 0 and math.min(1, current / total) or 0
            report("正在下载更新包", math.floor(2 + ratio * 68), current, total)
        end,
    })
    pcall(handle.close,handle)
    if not called or not ok then return fail(called and err or "下载更新包异常") end
    if self.backend:identity(archive)~=archive_identity then return fail("更新包文件已变化") end

    local archive_size = lfs.attributes(archive, "size")
    local size = tonumber(archive_size) or 0
    if size ~= tonumber(release.size) then
        return fail("更新包大小校验失败")
    end
    report("正在校验 SHA-256", 76)
    local actual, hash_err = self.backend.files:hash(archive)
    if not actual or actual:lower() ~= release.sha256 or self.backend:identity(archive)~=archive_identity then
        return fail(hash_err or "SHA-256 校验失败")
    end

    report("正在安全解压", 86)
    local extracted,unpacked,unpack_err=pcall(self._extractPackage,self,archive,stage)
    if not extracted or not unpacked then return fail(extracted and unpack_err or "更新包解压异常") end
    local handed,handoff_error=self.staging:handoff();if not handed then return fail(handoff_error) end
    if not self.backend:validate(self.backend.paths.stage,release.version) then return fail("更新包产品、结构或版本不正确") end

    report("正在备份并安装", 96)
    local installed,install_error=tx:install(self.current_version,release.version,function()
        local state=self.settings:update();state.pending_version=release.version;state.available=nil
        return self.settings:flush()
    end)
    if not installed then return fail(install_error) end
    self.busy=false;self.restart_required=true;Guard.block()
    local cleaned,cleanup_error=self.staging:cleanup()
    report("安装完成", 100)
    return true,not cleaned and cleanup_error or nil
end

function Updater:confirmInstalledUpdate()
    local ok,err=self:recoverUpdate();if not ok then return nil,err end
    if self.restart_required then return nil,"旧版本已恢复，请重启 KOReader" end
    local record=self.transaction:_load();if not record or record.phase~="confirmed" then return false end
    local state=self.settings:update();local prior=state.pending_version
    state.pending_version=nil
    local called,saved=pcall(self.settings.flush,self.settings)
    if not called or not saved then state.pending_version=prior;return nil,"更新确认状态保存失败，备份已保留" end
    return true
end

function Updater:koreaderVersion()
    return Version:getShortVersion()
end

return Updater
