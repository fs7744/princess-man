local context = require("man.core.context")
local manager = require('man.config.manager')
local response = require("man.core.response")
local call_func = require('man.core.utils').call_func

local _M = { priority = 20960, name = "faq-check" }

function _M.rewrite(ctx)
    local conf = ctx.matched_router.faq_check
    if not conf or not context.is_req_in_allow_list(ctx, conf.allow) then
        return
    end
    local faq = manager.get_custom_configs('global_faq')
    if faq then
        local offline = faq.offline
        if offline and context.is_req_in_allow_list(ctx, offline.allow) then
            return response.exit(502, offline.body)
        end
    end
    call_func(conf.func, ctx)
end

return _M
