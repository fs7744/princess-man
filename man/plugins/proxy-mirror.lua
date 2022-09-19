local request = require('man.core.request')
local log = require('man.core.log')
local math_random = math.random

local _M = { priority = 18000, name = "proxy-mirror" }

function _M.rewrite(ctx)
    local conf = ctx.matched_router.mirror
    if not conf then
        return
    end
    if not conf.sample_ratio or conf.sample_ratio == 1 or math_random() <
        conf.sample_ratio then
        request.set_var(ctx, 'upstream_mirror_host', conf.host)
    end
end

return _M
