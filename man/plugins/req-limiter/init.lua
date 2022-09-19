local request = require("man.core.request")
local qps = require("man.plugins.req-limiter.qps")

local _M = { priority = 20900, name = "req-limiter" }

function _M.rewrite(ctx)
    local conf = ctx.matched_router.limit_req
    if not conf then
        return
    end

    if conf.rate then
        request.set_var(ctx, 'limit_rate', conf.speed)
    end

    if conf.qps and qps.limit(ctx, conf.qps) then
        return
    end
end

return _M
