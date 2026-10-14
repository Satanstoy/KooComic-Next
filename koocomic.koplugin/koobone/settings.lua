local Settings = {}
Settings.__index = Settings

local function defaults()
    return {
        schema_version = 4,
        account = {
            email = "",
            password = nil,
            remember_password = false,
            vlibsid = nil,
            kbskey = nil,
            uin = nil,
            nick = nil,
        },
        download = {
            directory = nil,
            records = {},
        },
        update = {
            product_id = "koocomic-next",
            -- New installations check once per day by default. This only
            -- checks the manifest and shows a prompt; installation still
            -- requires explicit user confirmation.
            auto_check_enabled = true,
            last_auto_update_check_at = 0,
            last_update_prompt_date = "",
            update_prompt_later_count = 0,
            auto_update_prompt_disabled = false,
            last_seen_update_version = "",
            available = nil,
            pending_version = nil,
        },
        ui = {
            portrait_columns = 3,
            portrait_rows = 2,
            landscape_columns = 4,
            landscape_rows = 2,
            text_size = "large",
            series_style = "divider",
        },
        preprocess = {strength=0.8,scale_mode="original",algorithm_version="kissfft-f2892a2-v1"},
    }
end

local function merge(target, source)
    if type(source) ~= "table" then return target end
    for key, value in pairs(source) do
        if type(value) == "table" and type(target[key]) == "table" then
            merge(target[key], value)
        else
            target[key] = value
        end
    end
    return target
end

local function copy(value)
    if type(value)~="table" then return value end
    local result={};for key,item in pairs(value) do result[key]=copy(item) end;return result
end

function Settings:new(path, legacy_path,options)
    options=options or {}
    local object = setmetatable({
        path = assert(path, "settings path required"),
        persistence = options.persistence or require("koobone.settings_store"):new{path=path,legacy_path=legacy_path},
        legacy_path = legacy_path,
    }, self)
    object:load()
    return object
end

function Settings:load()
    local payload,read_error=self.persistence:load(self.path)
    assert(not read_error,"settings cannot be read; original preserved")
    assert(payload==nil or type(payload)=="table","invalid settings payload")
    self.payload=copy(payload or {})
    local source=payload and self.path
    local data = payload and payload.data
    local source_schema
    if type(data)=="table" then source_schema=data.schema_version end
    assert(data==nil or type(data)=="table","invalid settings data")
    if type(data) ~= "table" then
        local legacy
        if self.legacy_path and self.legacy_path ~= self.path then
            local old,err=self.persistence:load(self.legacy_path)
            assert(not err,"legacy settings cannot be read; original preserved")
            assert(old==nil or type(old)=="table","invalid legacy settings payload")
            if old then
                if old.data~=nil then legacy=old.data else legacy=old.settings end
            end
            if legacy~=nil then source=self.legacy_path end
        end
        if legacy==nil and payload then legacy=payload.settings end
        assert(legacy==nil or type(legacy)=="table","invalid legacy settings; original preserved")
        if type(legacy) == "table" then
            source_schema=legacy.schema_version
            if type(legacy.account) == "table" then
                data = copy(legacy)
            else
                data = merge(defaults(),copy(legacy))
                data.account.email = legacy.email or ""
                data.account.remember_password=legacy.remember_password==true
                data.account.password=legacy.password
                data.account.vlibsid = legacy.vlibsid
                data.account.kbskey = legacy.kbskey
                data.account.uin = legacy.uin
                data.account.nick = legacy.nick
            end
        else
            data = defaults()
        end
    end
    assert(source_schema==nil or (type(source_schema)=="number" and source_schema>=1 and
        source_schema<=4 and source_schema==math.floor(source_schema)),"unsupported settings schema; original preserved")
    for _,section in ipairs({"account","download","update","ui","preprocess"}) do
        assert(data[section]==nil or type(data[section])=="table","invalid settings section; original preserved")
    end
    assert(not data.download or data.download.records==nil or type(data.download.records)=="table","invalid download records")
    self.migration_source=(source_schema~=4) and source or nil
    data=merge(defaults(),copy(data))
    if data.account.remember_password ~= true then
        data.account.password = nil
    end
    data.schema_version = 4
    data.update.product_id="koocomic-next"
    if data.update.available and (type(data.update.available)~="table" or data.update.available.product_id~="koocomic-next") then
        data.update.available=nil
    end
    if self.migration_source then data.update.pending_version=nil end
    local styles={divider=true,ribbon=true,stack=true,collage=true,text=true,none=true}
    if not styles[data.ui.series_style] then data.ui.series_style="divider" end
    self.data = data
    self:flush()
end

function Settings:flush()
    local active,reason=require("koobone.runtime_guard").ensure();if not active then return nil,reason end
    local payload=copy(self.payload or {})
    payload.data=copy(self.data)
    local ok,err=self.persistence:save(self.path,payload,self.migration_source)
    assert(ok,"settings save failed; original preserved: "..tostring(err))
    self.payload,self.migration_source=payload,nil
    self.warning=err
    return true
end

function Settings:account()
    return self.data.account
end

function Settings:download()
    return self.data.download
end

function Settings:update()
    return self.data.update
end

function Settings:ui()
    return self.data.ui
end

function Settings:setCredentials(email, password, remember)
    local account = self:account()
    account.email = tostring(email or "")
    account.remember_password = remember == true
    account.password = account.remember_password and tostring(password or "") or nil
    self:flush()
end

function Settings:clearPassword()
    local account = self:account()
    account.password = nil
    account.remember_password = false
    self:flush()
end

function Settings:clearSession()
    local account = self:account()
    account.vlibsid = nil
    account.kbskey = nil
    account.uin = nil
    account.nick = nil
    self:flush()
end

function Settings:logout()
    self:clearSession()
    self:clearPassword()
end

return Settings
