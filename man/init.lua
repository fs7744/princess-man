local log = require("man.core.log")
local utils = require("man.core.utils")
local timers = require("man.core.timers")
local events = require("man.core.events")
local config = require("man.config.manager")
local json = require("man.core.json")
local router = require("man.router")
local sni = require("man.router.sni")
local l4 = require("man.router.l4")
local stream_context = require("man.stream.context")
local balancer = require("man.balancer")

local _M = {}

function _M.init(params)
    require("resty.core")

    if require("man.core.os").osname() == "Linux" then
        require("ngx.re").opt("jit_stack_size", 200 * 1024)
    end

    require("jit.opt").start("minstitch=2", "maxtrace=4000", "maxrecord=8000",
        "sizemcode=64", "maxmcode=4000", "maxirconst=1000")
    local process = require("ngx.process")
    local ok, err = process.enable_privileged_agent()
    if not ok then
        log.error("failed to enable privileged_agent: ", err)
    end
    params = json.decode(params)
    ok, err = config.init(params)
    if err then
        log.error("failed to init config: ", err)
    end
    events.init()
end

function _M.stream_init_worker()
    utils.randomseed()
    timers.init_worker()
    config.init_worker()
    events.init_worker()
    router.init_worker()
end

function _M.stream_ssl_certificate()
    local ctx = stream_context.new_api_context()
    sni.match_router(ctx)
end

function _M.stream_preread()
    local ctx = stream_context.get_api_context()
    if not ctx then
        ctx = stream_context.new_api_context()
    end
    if not ctx.matched_router then
        l4.match_router(ctx)
    end
    if not ctx.matched_router then
        sni.match_router(ctx)
    end

    balancer.prepare(ctx)
end

function _M.stream_balancer()
    local ctx = stream_context.get_api_context()
    if ctx and ctx.matched_router then
        log.error('stream_balancer ', ctx.matched_router.id)
        local server = ctx.matched_router.node[1]

        local ok, err = require("ngx.balancer").set_current_peer(server.host, server.port)
        log.error('stream_balancer ', server.host, server.port, ok, err)
    else
        log.error('stream_balancer no matched_router')
        ngx.exit(502)
    end
end

function _M.stream_log()
    local ctx = stream_context.get_api_context()
    if ctx then
        log.error('stream_log hostname: ', ctx.var.hostname, ' protocol: ', ctx.var.protocol, ' server_addr: ',
            ctx.var.server_addr,
            ' server_port: ', ctx.var.server_port)
        stream_context.clear_api_context()
    end

end

return _M
