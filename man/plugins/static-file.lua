local context = require('man.core.context')
local response = require('man.core.response')
local template = require('resty.template')

local _M = { priority = 18400, name = "static-file" }

function _M.rewrite(ctx)
    local conf = ctx.matched_router.static_file
    if not conf then
        return
    end
    local c
    for _, m in ipairs(conf) do
        if context.is_req_in_allow_list(ctx, m.allow) then
            c = m
            break
        end
    end
    if not c then
        return
    end
    if c.content_type then
        response.set_header('Content-Type', c.content_type)
    end
    if c.is_template == true then
        response.exit(200, template.process(c.content, ctx))
    else
        response.exit(200, c.content)
    end

end

return _M
