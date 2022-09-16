local process = require("ngx.process")
local signal = require('resty.signal')

local _M = {}

function _M.reload()
    return signal.kill(process.get_master_pid(), signal.signum("HUP"))
end

function _M.quit()
    return signal.kill(process.get_master_pid(), signal.signum("QUIT"))
end

function _M.reopen_log()
    return signal.kill(process.get_master_pid(), signal.signum("USR1"))
end

function _M.is_privileged_agent()
    return process.type() == "privileged agent"
end

function _M.subsystem()
    return ngx.config.subsystem
end

function _M.is_http_system()
    return _M.subsystem() == 'http'
end

return _M
