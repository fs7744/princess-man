local log = require("man.core.log")
local stream_context = require("man.stream.context")

local _M = {}

function _M.init()
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
end

function _M.stream_init_worker()

end

function _M.stream_preread()
    local ctx = stream_context.new_api_context()
    log.error('hostname: ', ctx.var.hostname, ' protocol: ', ctx.var.protocol, ' server_addr: ', ctx.var.server_addr,
        ' server_port: ', ctx.var.server_port)
end

function _M.stream_balancer()
    local ctx = stream_context.get_api_context()
    log.error('stream_balancer hostname: ', ctx.var.hostname, ' protocol: ', ctx.var.protocol, ' server_addr: ',
        ctx.var.server_addr,
        ' server_port: ', ctx.var.server_port)
end

function _M.stream_log()
    local ctx = stream_context.get_api_context()
    log.error('stream_log hostname: ', ctx.var.hostname, ' protocol: ', ctx.var.protocol, ' server_addr: ',
        ctx.var.server_addr,
        ' server_port: ', ctx.var.server_port)
    stream_context.clear_api_context()
end

return _M
