local str = require('man.core.string')
local config = require('man.config.manager')
local log = require("man.core.log")

local _M = { current = {} }

function _M.filter(v)
    if type(v) ~= 'table' then
        return false
    end
    local listen = str.lower(v.listen)
    if str.has_prefix(listen, '0.0.0.0')
        or str.has_prefix(listen, '127.0.0.1')
        or str.has_prefix(listen, 'localhost') then
        return true
    end
    local params = config.get_config('params')
    if params and params.local_ips and type(params.local_ips) == 'table' then
        for _, value in ipairs(params.local_ips) do
            if str.re_find(listen, value) then
                return true
            end
        end
    end
    return false
end

function _M.init_router_metadata(r)
    local p = str.split(r.listen, ':')
    return {
        paths = p[2],
        metadata = r
    }
end

local match_opts = {}
function _M.match_router(ctx)
    if _M.router then
        local metadata, err = _M.router:match(ctx.var.server_port, match_opts)
        if metadata then
            ctx.matched_router = metadata
        elseif err then
            log.error(err)
        end
    end
end

return _M
