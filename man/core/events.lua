local ev = require("resty.worker.events")
local exiting = ngx.worker.exiting
local ngp = require("man.core.ngp")
local log = require("man.core.log")

local _M = { handlers = {} }

function _M.register(key, handler, reset)
    log.info("register event handler: ", key)
    if reset then
        _M.handlers[key] = {}
    end
    local old = _M.handlers[key]
    if not old then
        old = {}
    end

    old[#old + 1] = handler
    _M.handlers[key] = old
end

local function call_handler(handler, data, event, source, pid)
    local _, err = pcall(handler, data, source, pid)
    if err ~= nil then
        log.error("received source=", source, " ;event=", event, " ;err=", err)
    end
end

local function handle(data, event, source, pid)
    log.info("received source=", source, " ;event=", event)
    local handler = _M.handlers[event]
    if handler and not exiting() then
        for _, h in ipairs(handler) do
            call_handler(h, data, event, source, pid)
        end
    end
end

function _M.init_worker()
    _M.ev = ev
    _M.is_privileged = ngp.is_privileged_agent()
    local ok, err = ev.configure { interval = 0.1, shm = "process_events" }
    if not ok then
        return err
    end
    ev.register(handle)
end

return _M
