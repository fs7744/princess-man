local log = require('man.core.log')
local lock = require('man.core.lock')
local request = require('man.core.request')
local response = require('man.core.response')
local limit_req_new = require("resty.limit.count").new

local _M = { timeout = 0.5,
    exptime = 1 }

local function create_limiter(conf)
    return limit_req_new('plugin-qps-limit', conf.requests, conf.window)
end

function _M.limit(ctx, conf)
    local lim = ctx.matched_router._lim
    local err
    if not lim then
        local cahceId = "limit-qps" .. ctx.matched_router.id ..
            ctx.matched_router._version
        ctx.matched_router._lim_key = cahceId
        lim, err = lock.run(cahceId, _M, create_limiter, conf)
        ctx.matched_router._lim = lim
        if not lim then
            request.set_var(ctx, 'reason', 'block: limit-qps failed')
            log.error("failed get plugin-qps-limit cache: ", err)
            response.exit(500, conf.content)
            return true
        end
    end

    local key = ctx.matched_router._lim_key .. (ctx.var[conf.key] or "")
    log.info("qps limit key: ", key)
    local delay
    delay, err = lim:incoming(key, true)
    if not delay then
        if err == "rejected" then
            request.set_var(ctx, 'reason', 'block: limit-qps rejected')
            response.exit(503, conf.content)
            return true
        end

        request.set_var(ctx, 'reason', 'block: limit-qps failed')
        log.error("failed to limit qps: ", err)
        response.exit(500, conf.content)
        return true
    end
end

return _M
