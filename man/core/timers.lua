local table = require('man.core.table')
local log = require('man.core.log')
local ngp = require("man.core.ngp")
local sleep = require("man.core.utils").sleep
local pairs = pairs
local timer_every = ngx.timer.every
local timer_at = ngx.timer.at
local current_time_millis = require('man.core.time').current_time_millis

local _M = {}

local function _internal(timer)
    timer.start_time = current_time_millis()

    repeat
        local ok, err = pcall(timer.callback_fun)
        if not ok then
            log.error("failed to run the timer: ", timer.name, " err: ", err)

            if timer.sleep_fail > 0 then
                sleep(timer.sleep_fail)
            end

        elseif timer.sleep_succ > 0 then
            sleep(timer.sleep_succ)
        end

    until timer.each_ttl <= 0 or current_time_millis() >= timer.start_time +
        timer.each_ttl
end

local function run_timer(premature, self)
    if self.running or premature then
        return
    end

    self.running = true

    local ok, err = pcall(_internal, self)
    if not ok then
        log.error("failed to run timer[", self.name, "] err: ", err)
    end

    self.running = false
end

function _M.new(name, callback_fun, opts)
    if not name then
        return nil, "missing argument: name"
    end

    if not callback_fun then
        return nil, "missing argument: callback_fun"
    end

    opts = opts or {}
    local timer = {
        name = name,
        each_ttl = opts.each_ttl or 1,
        sleep_succ = opts.sleep_succ or 1,
        sleep_fail = opts.sleep_fail or 5,
        start_time = 0,

        callback_fun = callback_fun,
        running = false
    }

    local hdl, err = timer_every(opts.check_interval or 1, run_timer, timer)
    if not hdl then
        return nil, err
    end

    hdl, err = timer_at(0, run_timer, timer)
    if not hdl then
        return nil, err
    end

    return timer
end

local timers = {}

local function background_timer()
    if table.nkeys(timers) == 0 then
        return
    end

    for name, timer in pairs(timers) do
        log.info("run timer[", name, "]")
        pcall(timer)
    end
end

function _M.init_worker()
    if not ngp.is_privileged_agent() then
        return
    end
    local opts = { each_ttl = 0, sleep_succ = 0.01, check_interval = 1 }
    local timer, err = _M.new("background", background_timer, opts)
    if not timer then
        log.error("failed to create background timer: ", err)
        return
    end

    log.notice("succeed to create background timer")
end

function _M.register_timer(name, f, privileged)
    if privileged and not ngp.is_privileged_agent() then
        return
    end

    timers[name] = f
end

function _M.unregister_timer(name, privileged)
    if privileged and not ngp.is_privileged_agent() then
        return
    end

    timers[name] = nil
end

return _M
