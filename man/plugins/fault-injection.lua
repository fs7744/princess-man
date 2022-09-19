local context = require("man.core.context")
local response = require("man.core.response")
local sleep = require("man.core.utils").sleep
local math_random = math.random

local _M = { priority = 30000, name = "fault-injection" }

local function sample_hit(percentage)
    if not percentage then
        return true
    end

    return math_random() <= percentage
end

function _M.rewrite(ctx)
    local conf = ctx.matched_router.fault_injection
    if not conf then
        return
    end

    if conf.allow and context.is_req_in_allow_list(ctx, conf.allow) then
        local delay = conf.delay
        if delay and sample_hit(delay.percentage) then
            sleep(delay.duration)
        end

        local abort = conf.abort
        if abort and sample_hit(abort.percentage) then
            response.exit(abort.status, abort.body)
        end
    end
end

return _M
