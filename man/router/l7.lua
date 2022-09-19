local clear_table = require("man.core.table").clear
local log = require("man.core.log")

local _M = { current = {} }

function _M.filter(v)
    return v ~= true
end

function _M.init_router_metadata(r)
    return {
        paths = r.paths,
        hosts = r.host,
        remote_addrs = r.remote_addrs,
        methods = r.methods,
        priority = r.priority,
        metadata = r
    }
end

local match_opts = {}
function _M.match_router(ctx)
    if _M.router then
        clear_table(match_opts)
        match_opts.method = ctx.var.request_method
        match_opts.host = string.lower(ctx.var.host)
        match_opts.remote_addr = ctx.var.remote_addr
        local metadata, err = _M.router:match(string.lower(ctx.var.uri), match_opts)
        if metadata then
            ctx.matched_router = metadata
        elseif err then
            log.error(err)
        end
    end
end

return _M
