local log = require('man.core.log')
local edgep = require('man.core.edgep')
local timers = require('man.core.timers')
local time = require('man.core.time')
local str = require('man.core.string')
local f = require('man.core.file')
local lfs = require("lfs")

local INTERVAL = 60 * 60 -- rotate interval (unit: second)

local _M = { priority = 0, MAX_KEEP = 3 }

local function rotate_file(logDir, date_str, filename)
    log.info("rotate log_dir:", logDir)
    log.info("rotate filename:", filename)

    local new_filename = date_str .. "__" .. filename
    local file_path = logDir .. new_filename
    if f.exists(file_path) then
        log.info("file exist: ", file_path)
        return false
    end

    local file_path_org = logDir .. filename
    local ok, msg = os.rename(file_path_org, file_path)
    log.info("move file from ", file_path_org, " to ", file_path, " res:", ok,
        " msg:", msg)

    return true
end

local function tab_sort(a, b)
    return a > b
end

local function scan_log_folder(logDir)
    local t = { access = {}, error = {} }

    local access_name = "access.log"
    local error_name = "error.log"
    for file in lfs.dir(logDir) do
        local n = str.find_last(file, "__")
        if n ~= nil then
            local log_type = file:sub(n)
            if log_type == access_name then
                table.insert(t.access, file)
            elseif log_type == error_name then
                table.insert(t.error, file)
            end
        end
    end

    table.sort(t.access, tab_sort)
    table.sort(t.error, tab_sort)
    return t
end

local function init_max_keep()
    if not _M._MAX_KEEP then
        local manager = require('man.config.manager')
        if manager and manager.loader then
            local system = manager.get_custom_configs('system')
            if system and system.max_log_keep then
                _M._MAX_KEEP = true
                _M.MAX_KEEP = system.max_log_keep
            end
        end
    end
    return _M.MAX_KEEP
end

local function rotate()
    local now = time.current_time_millis()
    if _M.wait_time then
        if (now - _M.wait_time) > INTERVAL then
            _M.wait_time = now
        else
            return
        end
    else
        _M.wait_time = now
        return
    end

    local max_keep = init_max_keep()
    local prefix = ngx.config.prefix()
    local logDir = prefix .. 'logs/'

    ngx.update_time()
    local time = ngx.time()
    local date_str = os.date("%Y-%m-%d_%H", time)

    local ok1 = rotate_file(logDir, date_str, "access.log")
    local ok2 = rotate_file(logDir, date_str, "error.log")
    if not ok1 and not ok2 then
        return
    end

    log.warn("send USER1 signal to master process for reopening log file")
    local ok, err = edgep.reopen_log()
    if not ok then
        log.error("failed to reopening log file: ", err)
    end

    local log_list = scan_log_folder(logDir)
    for i = max_keep + 1, #log_list.access do
        local path = logDir .. log_list.access[i]
        ok = os.remove(path)
        log.warn("remove old access log file: ", path, " ret: ", ok)
    end

    for i = max_keep + 1, #log_list.error do
        local path = logDir .. log_list.error[i]
        ok = os.remove(path)
        log.warn("remove old error log file: ", path, " ret: ", ok)
    end
end

function _M.init()
    timers.register_timer('log-rotate', rotate, true)
end

function _M.destroy()
    timers.unregister_timer('log-rotate', true)
end

return _M
