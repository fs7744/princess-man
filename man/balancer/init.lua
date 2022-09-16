local response         = require('man.core.response')
local log              = require('man.core.log')
local balancer         = require("ngx.balancer")
local json             = require("man.core.json")
local set_more_tries   = balancer.set_more_tries
local get_last_failure = balancer.get_last_failure
local set_timeouts     = balancer.set_timeouts
local enable_keepalive = balancer.enable_keepalive and require('man.core.ngp').is_http_system() -- need patch
local priority         = require('man.balancer.priority')
local up               = require('man.balancer.upstream')
local lock             = require("man.core.lock")

local _M = {
    timeout = 1,
    exptime = 5
}


local global_timeout = { connect = 60, send = 60, read = 60 }
local function set_balancer_opts(upstream_conf)
    local conf = upstream_conf.balancer
    local timeout
    if conf and conf.timeout then
        timeout = conf.timeout
    else
        timeout = global_timeout
    end
    if timeout then
        local ok, err =
        set_timeouts(timeout.connect, timeout.send, timeout.read)
        if not ok then
            log.error("could not set upstream timeouts: ", err)
        end
    end

    if conf and conf.retries and conf.retries > 0 then
        local ok, err = set_more_tries(conf.retries)
        if not ok then
            log.error("could not set upstream retries: ", err)
        elseif err then
            log.warn("could not set upstream retries: ", err)
        end
    end
end

local function pick_server(ctx)
    return priority.pick_server(ctx)
end

_M.pick_server = pick_server

local function init_router(k, metadata)
    --log.info('first init router: ', k, ' ', json.encode(metadata))
    local success = pcall(up.init_router, k, metadata)
    if success then
        metadata._inited = true
    else
        return nil, 'init router failed'
    end
end

local function try_init_router(metadata)
    log.error("try_init_router: ", metadata._inited)
    if not metadata._inited then
        local id = metadata.id
        log.error("try_init_router: ", metadata.id)
        local _, e = lock.run(id, _M, init_router, id, metadata)
        if e then
            log.error('init router: ', id, ', err: ', e)
        end
    end
end

local rewrite_req
if require('man.core.ngp').is_http_system() then
    local request = require('man.core.request')

    function _M.prepare(ctx)
        local conf = ctx.matched_router
        if conf == nil then
            return response.exit(404)
        end
        try_init_router(conf)
        local server, err = pick_server(ctx)
        ctx.picked_server = server
        if not server then
            log.error("failed to pick server: ", err)
            return response.exit(404)
        end
        return true
    end

    function rewrite_req(ctx, server, allow_recreate)

        local recreate_request = false
        if server.proxy_host then
            request.set_header(ctx, 'host', server.proxy_host)
            ngx.var.proxy_host = server.proxy_host
            recreate_request = true
        end

        local conf = server.rewrite
        if not conf then
            return
        end
        if conf.requestHeaders ~= nil then
            for _, h in ipairs(conf.requestHeaders) do
                local var
                if h.matchType == 'const' then
                    var = h.value
                else
                    --var = context.get_req_var(ctx, h.value, h.matchType)
                end
                request.set_header(ctx, h.header, var)
                recreate_request = true
            end
        end
        if allow_recreate and recreate_request then
            local _, err = balancer.recreate_request()
            if err then
                log.error(err)
            end
        end
    end
else
    function _M.prepare(ctx)
        local conf = ctx.matched_router
        if conf == nil then
            return response.exit(404)
        end
        try_init_router(conf)
        local server, err = pick_server(ctx)
        ctx.picked_server = server
        if not server then
            log.error("failed to pick server: ", err)
            return response.exit(404)
        end
        return true
    end

    function rewrite_req(ctx, server, allow_recreate)
    end
end

local global_keepalive = {
    pool_size = 6,
    timeout = 60,
    requests = 1000
}
local set_current_peer
do
    local keepalive_opt = {}
    function set_current_peer(server, router_conf)
        -- keep the feature when we change the openresty code
        if enable_keepalive then
            local keepalive
            if router_conf and router_conf.balancer then
                keepalive = router_conf.balancer.keepalive
            end
            if not keepalive then
                keepalive = global_keepalive
            end
            keepalive_opt.pool = server.pool
            keepalive_opt.pool_size = keepalive.pool_size
            local ok, err = balancer.set_current_peer(server.host, server.port, keepalive_opt)
            if not ok then
                return ok, err
            end

            return balancer.enable_keepalive(keepalive.timeout, keepalive.requests)
        end

        return balancer.set_current_peer(server.host, server.port)
    end
end

local function report_failure(ctx, server)
    local checker = ctx._upstream.checker
    if checker and server then
        local state, code = get_last_failure()
        if state == "failed" then
            if code == 504 then
                checker:report_timeout(server.host, server.port, server.host)
            else
                checker:report_tcp_failure(server.host, server.port, server.host)
            end
        else
            checker:report_res_status(server.host, server.port, server.host,
                code)
        end
    end
end

function _M.run(ctx)
    local server, err
    if ctx.picked_server then
        server = ctx.picked_server
        ctx.picked_server = nil
        set_balancer_opts(ctx.matched_router)
    else
        report_failure(ctx, ctx.proxy_server)
        server, err = pick_server(ctx)
        if not server then
            log.error("failed to pick server: ", err)
            return response.exit(502)
        end
        rewrite_req(ctx, server, true)
    end
    ctx.proxy_server = server
    local ok
    ok, err = set_current_peer(server, ctx.matched_router)
    if not ok then
        log.error("failed to set the current peer: ", err)
        return response.exit(502)
    end
    ctx.proxy_passed = true
end

return _M
