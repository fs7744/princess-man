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

function _M.init()
    local opts = {
        listening = "unix:/tmp/events.sock",
    }

    local ev = require("resty.events").new(opts)
    if not ev then
        ngx.log(ngx.ERR, "failed to new events object")
    end

    _M.ev = ev
end

function _M.init_worker()
    _M.is_privileged = ngp.is_privileged_agent()
    _M.ev:subscribe("*", "*", handle)
    local ok, err = _M.ev:init_worker()
    if not ok then
        ngx.log(ngx.ERR, "failed to init events: ", err)
    end
end

function _M.run()
    _M.ev:run()
end

function _M.publish_all(source, event, data)
    _M.ev:publish('all', source, event, data)
end

function _M.publish_local(source, event, data)
    _M.ev:publish('current', source, event, data)
end

return _M
