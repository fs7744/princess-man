local context = require("man.core.context")
local manager = require('man.config.manager')
local response = require("man.core.response")

local _M = { name = "faq" }

function _M.rewrite(ctx)
    local faq = manager.get_custom_configs('global_faq')
    if faq then
        local offline = faq.offline
        if offline and context.is_req_in_allow_list(ctx, offline.allow) then
            return response.exit(502, offline.body)
        end
        if faq.bypass and context.is_req_in_allow_list(ctx, faq.bypass) then
            return
        end
        return response.exit(200, faq.body)
    end
    response.exit(200)
end

return _M
