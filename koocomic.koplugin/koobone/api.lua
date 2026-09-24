local JSON = require("json")
local ltn12 = require("ltn12")
local socketutil = require("socketutil")
local http = require("socket.http")
local Util = require("koobone.util")

local Api = {}
Api.__index = Api

Api.BASE = "https://bookof.hk"
Api.WEB_VERSION = "7"
Api.CLIENT_VERSION = "KOOBONE/5.0.0"
-- bookof.hk currently returns only {"msgid":"e499"} when its login
-- endpoint receives a non-browser User-Agent. Keep the official X-KB-FROM
-- header for source/version information while using a browser-compatible UA
-- for site requests, matching the web client this adapter implements.
Api.USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 " ..
    "(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"

function Api:new(settings)
    return setmetatable({ settings = assert(settings, "settings required") }, self)
end

function Api:headers(extra, include_session)
    local headers = {
        ["Accept"] = "*/*",
        ["User-Agent"] = self.USER_AGENT,
        ["X-KB-FROM"] = self.CLIENT_VERSION .. " WEB(" .. self.WEB_VERSION .. ") GET /web.htm",
        ["Referer"] = self.BASE .. "/web.htm",
    }
    if include_session ~= false then
        local account = self.settings:account()
        local cookies = {}
        if account.vlibsid then cookies[#cookies + 1] = "VLIBSID=" .. account.vlibsid end
        if account.kbskey then cookies[#cookies + 1] = "KBSKEY=" .. account.kbskey end
        if #cookies > 0 then headers["Cookie"] = table.concat(cookies, "; ") end
    end
    for key, value in pairs(extra or {}) do headers[key] = value end
    return headers
end

function Api:request(options)
    options = options or {}
    local chunks
    if not options.sink then
        chunks = {}
        options.sink = socketutil.table_sink(chunks)
    end
    options.headers = options.headers or self:headers(nil, options.include_session)
    options.redirect = options.redirect == true
    socketutil:set_timeout(options.block_timeout or 20, options.total_timeout or 90)
    -- KOReader's LuaSocket performs its own HTTPS adjustment when an https://
    -- URL is passed to socket.http.request. Calling ssl.https.request directly
    -- bypasses that compatibility path on some Kindle builds and can fail for
    -- redirected CDN downloads even though the JSON requests still work.
    local called, first, raw_code, headers, status = pcall(http.request, options)
    socketutil:reset_timeout()
    if not called then return nil, Util.cleanMessage(first) end
    local code = tonumber(raw_code)
    if not code then
        -- LuaSocket returns nil, error_message for transport failures. Preserve
        -- the second value before converting HTTP status codes to numbers.
        return nil, Util.cleanMessage(status or raw_code or first or "network error")
    end
    local body = chunks and table.concat(chunks) or first
    return {
        code = code,
        headers = headers or {},
        status = status,
        body = body,
    }
end

function Api:requestOk(options, accepted)
    local response, err = self:request(options)
    if not response then return nil, err end
    accepted = accepted or { [200] = true }
    if not accepted[response.code] then
        return nil, "HTTP " .. tostring(response.code) .. " " ..
            Util.cleanMessage(response.status, 100)
    end
    return response
end

function Api:requestJson(options)
    local response, err = self:requestOk(options)
    if not response then return nil, err end
    local ok, data = pcall(JSON.decode, response.body or "")
    if not ok or type(data) ~= "table" then return nil, "服务器返回了无效数据" end
    return data, response
end

function Api:getInitialSession()
    -- /login.htm is only the static login page and currently does not create
    -- a session. /login.php does; the site root is retained as a fallback
    -- because it also creates VLIBSID before redirecting to /login.htm.
    local attempts = {
        {
            path = "/login.php?goto=web.htm",
            from = "GET /login.php",
        },
        {
            path = "/",
            from = "GET /",
        },
    }
    local last_error
    for _, attempt in ipairs(attempts) do
        local response, err = self:request{
            url = self.BASE .. attempt.path,
            method = "GET",
            include_session = false,
            headers = self:headers({
                ["X-KB-FROM"] = self.CLIENT_VERSION .. " WEB(" ..
                    self.WEB_VERSION .. ") " .. attempt.from,
            }, false),
        }
        if response and (response.code == 200 or response.code == 302) then
            local sid = Util.cookieValue(
                Util.header(response.headers, "set-cookie"), "VLIBSID")
            if sid then
                self.settings:account().vlibsid = sid
                self.settings:flush()
                return true
            end
            last_error = "初始化页面没有返回 VLIBSID"
        elseif response then
            last_error = "初始化登录会话失败：HTTP " .. tostring(response.code)
        else
            last_error = err
        end
    end
    return nil, last_error or "无法初始化登录会话"
end

local function multipart(fields)
    local boundary = "----KOReaderKoobone" .. tostring(os.time()) .. tostring(math.random(1000, 9999))
    local parts = {}
    for key, value in pairs(fields) do
        parts[#parts + 1] = "--" .. boundary .. "\r\n"
        parts[#parts + 1] = 'Content-Disposition: form-data; name="' .. key .. '"\r\n\r\n'
        parts[#parts + 1] = tostring(value) .. "\r\n"
    end
    parts[#parts + 1] = "--" .. boundary .. "--\r\n"
    return table.concat(parts), boundary
end

local function hasValidUin(value)
    local numeric = tonumber(value)
    return numeric ~= nil and numeric > 0
end

function Api:login(email, password)
    local account = self.settings:account()
    if not account.vlibsid then
        local ok, err = self:getInitialSession()
        if not ok then return nil, err end
    end
    local body, boundary = multipart{
        email = email,
        passwd = password,
        keepalive = "1",
    }
    local response, err = self:requestOk{
        url = self.BASE .. "/login_do.php",
        method = "POST",
        source = ltn12.source.string(body),
        headers = self:headers({
            ["Content-Type"] = "multipart/form-data; boundary=" .. boundary,
            ["Content-Length"] = tostring(#body),
            ["Origin"] = self.BASE,
            ["Referer"] = self.BASE .. "/login.php?goto=web.htm",
            ["X-KB-FROM"] = self.CLIENT_VERSION .. " POST /login.php",
        }),
    }
    body = nil
    if not response then return nil, err end

    -- The web login endpoint uses HTTP 200 for both successful and failed
    -- authentication. Its current browser client checks the JSON `uin` field
    -- for success and shows `msg` on failure, so an HTTP status alone cannot
    -- be treated as a successful login.
    local decoded_ok, login_info = pcall(JSON.decode, response.body or "")
    if not decoded_ok or type(login_info) ~= "table" then login_info = nil end

    local set_cookie = Util.header(response.headers, "set-cookie")
    local key = Util.cookieValue(set_cookie, "KBSKEY")
    local refreshed_sid = Util.cookieValue(set_cookie, "VLIBSID")
    local has_uin = login_info and hasValidUin(login_info.uin) or false
    local response_code = login_info and tonumber(login_info.ret) or nil
    local message_id = login_info and Util.cleanMessage(login_info.msgid, 32) or ""

    -- Lua considers numeric zero truthy. KOOBONE uses `uin: 0` (together
    -- with `ret: -1`) for rejected credentials, so never test this field by
    -- truthiness alone as the site's JavaScript does.
    if login_info and (response_code and response_code < 0 or
            login_info.uin ~= nil and not has_uin) then
        local message = Util.cleanMessage(
            login_info.msg or login_info.message or login_info.error, 180)
        return nil, message ~= "" and message or "登录失败，请检查邮箱和密码"
    end

    if login_info and not has_uin then
        local message = Util.cleanMessage(
            login_info.msg or login_info.message or login_info.error, 180)
        if message ~= "" then return nil, message end
        if message_id == "e499" then
            return nil, "服务器拒绝了当前客户端请求（e499）"
        elseif message_id ~= "" then
            return nil, "登录失败（服务器代码：" .. message_id .. "）"
        end
    end

    -- The current endpoint can return the authenticated session key in the
    -- JSON `skey` field instead of a KBSKEY Set-Cookie header. Treat it as the
    -- same session secret only after a positive UIN has confirmed success.
    if not key and has_uin then
        local response_key = Util.trim(login_info.skey)
        if response_key ~= "" then key = response_key end
    end

    -- Newer sessions may authenticate the existing VLIBSID without issuing a
    -- KBSKEY. Keep accepting KBSKEY for the legacy flow, but let Auth:login()
    -- verify either form immediately through /uinfo.php before it is trusted.
    if not has_uin and not key then
        return nil, login_info and "登录失败，请检查邮箱和密码" or
            "服务器返回了无法识别的登录响应"
    end

    if refreshed_sid then account.vlibsid = refreshed_sid end
    if key then account.kbskey = key end
    self.settings:flush()
    return true, login_info
end

function Api:userInfo()
    local data, err = self:requestJson{
        url = self.BASE .. "/uinfo.php?v=web&ver=" .. self.WEB_VERSION,
        method = "GET",
        headers = self:headers(),
    }
    if not data then return nil, err end
    if not data.uin then return nil, "登录状态已失效或用户资料无效" end
    return data
end

function Api:library(limit)
    local account = self.settings:account()
    if not account.uin then return nil, "尚未登录" end
    local url = string.format("%s/vol_list.php?u=%s&by=time&limit=%d",
        self.BASE, tostring(account.uin), tonumber(limit) or 28)
    local data, err = self:requestJson{
        url = url,
        method = "GET",
        headers = self:headers(),
    }
    if not data then return nil, err end
    if type(data.data) ~= "table" then return nil, "书库响应无效或登录已过期" end
    return data
end

function Api:download(url, part_path, options)
    options = options or {}
    local handle, open_err = io.open(part_path, "wb")
    if not handle then return nil, open_err or "无法创建临时文件" end
    local received = 0
    local total_hint = tonumber(options.total) or 0
    local cancelled = false
    local sink_error
    local function sink(chunk, err)
        if chunk then
            if options.is_cancelled and options.is_cancelled() then
                cancelled = true
                return nil, "cancelled"
            end
            if tonumber(options.max_bytes) and received + #chunk > options.max_bytes then
                sink_error = "download exceeds size limit"
                return nil, sink_error
            end
            local ok, write_err = handle:write(chunk)
            if not ok then return nil, write_err end
            received = received + #chunk
            if options.on_progress then options.on_progress(received, total_hint) end
        end
        return 1
    end
    local response, err = self:request{
        url = url,
        method = "GET",
        include_session = false,
        redirect = true,
        headers = options.headers or {
            ["Accept"] = "*/*",
            ["User-Agent"] = self.USER_AGENT,
            ["X-KB-FROM"] = self.CLIENT_VERSION .. " WEB(" .. self.WEB_VERSION .. ") FETCH /web.htm",
            ["Referer"] = self.BASE .. "/",
        },
        sink = sink,
        block_timeout = socketutil.FILE_BLOCK_TIMEOUT,
        total_timeout = -1,
    }
    handle:close()
    if cancelled then return nil, "cancelled", received end
    if sink_error then return nil, sink_error, received end
    if not response then return nil, err, received end
    if response.code ~= 200 then return nil, "HTTP " .. tostring(response.code), received end
    if received <= 0 then return nil, "下载内容为空", received end
    return true, response.headers, received
end

return Api
