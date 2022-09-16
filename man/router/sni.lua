local ssl = require "ngx.ssl"
local log = require("man.core.log")

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
function _M.match_router(ctx)
    local server_name = ssl.server_name()
    if server_name then
        log.error('stream_preread stream_ssl_certificate ', server_name)
        if _M.router then
            local metadata, err = _M.router:match(string.lower(server_name):reverse(), match_opts)
            if metadata then
                ctx.matched_router = metadata
            elseif err then
                log.error(err)
            end
        end
    end
end

return _M
