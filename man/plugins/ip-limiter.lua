local ipmatcher = require("resty.ipmatcher")
local json = require('man.core.json')
local log = require('man.core.log')
local request = require('man.core.request')
local response = require('man.core.response')
local manager = require('man.config.manager')
local lrucache = require('man.core.lrucache').new({ ttl = 300, count = 512 })

local _M = { priority = 21000, name = "ip-limiter" }

local function create_ip_matcher(ip_list)
    local ip, err = ipmatcher.new(ip_list)
    if not ip then
        log.error("failed to create ip matcher: ", err, " ip list: ",
            json.encode(ip_list))
        return nil
    end

    return ip
end

local function try_limit_ip(ctx, conf)
    if not conf then
        return
    end

    local block = false
    local remote_addr = ctx.var.xip
    if conf.blacklist and #conf.blacklist > 0 then
        local matcher = lrucache(conf.blacklist, nil, create_ip_matcher,
            conf.blacklist)
        if matcher then
            block = matcher:match(remote_addr)
        end
    end

    if conf.whitelist and #conf.whitelist > 0 then
        local matcher = lrucache(conf.whitelist, nil, create_ip_matcher,
            conf.whitelist)
        if matcher then
            block = not matcher:match(remote_addr)
        end
    end

    if block then
        request.set_var(ctx, 'reason', 'block: ip ' .. remote_addr)
        response.exit(403, conf.content)
    end
end

function _M.rewrite(ctx)
    try_limit_ip(ctx, manager.get_custom_configs('global_limit_ip'))
    if not ctx._stop then
        try_limit_ip(ctx, ctx.matched_router.limit_ip)
    end
end

return _M
