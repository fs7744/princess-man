local log = require("man.core.log")
local utils = require("man.core.utils")
local timers = require("man.core.timers")
local events = require("man.core.events")
local config = require("man.config.manager")
local json = require("man.core.json")
local router = require("man.router")
local sni = require("man.router.sni")
local l4 = require("man.router.l4")
local plugin = require("man.core.plugin")
local context = require("man.core.context")
local balancer = require("man.balancer")
local exit = require("man.core.response").exit

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
    config.init_worker()
    timers.init_worker()
    events.init_worker()
    plugin.init_worker()
    router.init_worker()
end

function _M.stream_ssl_certificate()
    local ctx = context.new_api_context()
    sni.match_router(ctx)
end

function _M.stream_preread()
    local ctx = context.get_api_context()
    if not ctx then
        ctx = context.new_api_context()
    end
    if not ctx.matched_router then
        l4.match_router(ctx)
    end
    if not ctx.matched_router then
        sni.match_router(ctx)
    end
    if ctx.matched_router then
        plugin.run("preread", ctx)
    end
    if not balancer.prepare(ctx) then
        exit(503)
    end
end

function _M.stream_balancer()
    local ctx = context.get_api_context()
    balancer.run(ctx)
end

function _M.stream_log()
    local ctx = context.get_api_context()
    if ctx then
        log.error('stream_log hostname: ', ctx.var.hostname, ' protocol: ', ctx.var.protocol, ' server_addr: ',
            ctx.var.server_addr,
            ' server_port: ', ctx.var.server_port)
        context.clear_api_context()
    end

end

return _M
