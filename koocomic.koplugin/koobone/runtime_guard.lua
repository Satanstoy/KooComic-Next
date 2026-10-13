-- SPDX-License-Identifier: AGPL-3.0-only
local Guard={reason="插件代码已切换，请先重启 KOReader。"}
function Guard.block() Guard.blocked=true end
function Guard.ensure() if Guard.blocked then return nil,Guard.reason end;return true end
function Guard.busy(context)
    local downloader,preprocess=context.downloader,context.preprocess
    if downloader and downloader:isActive() or preprocess and (preprocess.running or preprocess:isActive()) then return true end
    local queue=downloader and downloader.service and downloader.service.queue
    if queue and not queue.paused then
        for _,job in ipairs(queue.jobs) do if job.state=="pending" or job.state=="preparing" then return true end end
    end
    local coordinator=preprocess and preprocess.coordinator
    return coordinator and coordinator:owner()~=nil or false
end
return Guard
