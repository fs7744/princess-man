local log = require('man.core.log')

local _M = {}

function _M.preread(ctx)
    log.error('preread hostname: ', ctx.var.hostname, ' protocol: ', ctx.var.protocol, ' server_addr: ',
        ctx.var.server_addr,
        ' server_port: ', ctx.var.server_port)
end

return _M
