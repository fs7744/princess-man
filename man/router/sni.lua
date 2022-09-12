local tb = require('man.core.table')
local log = require("man.core.log")
local radix = require("resty.radixtree")

local _M = { current = {} }

function _M.filter(v)
    return v ~= true
end

function _M.init_router_metadata(r)
    for i, s in ipairs(r.host) do
        r.host[i] = s:reverse()
    end
    return {
        paths = r.host,
        metadata = r
    }
end

local match_opts = {}
function _M.match_router(ctx, server_name)
    if _M.router then
        local metadata, err = _M.router:match(string.lower(server_name):reverse(), match_opts)
        if metadata then
            ctx.matched_router = metadata
        end
    end
end

return _M
