local str = require("man.core.string")
local ngx_sleep = ngx.sleep
local exiting = ngx.worker.exiting
local max_sleep_interval = 1

local _M = {}

local function sleep(sec)
    if sec <= max_sleep_interval then
        return ngx_sleep(sec)
    end
    ngx_sleep(max_sleep_interval)
    if exiting() then
        return
    end
    sec = sec - max_sleep_interval
    return sleep(sec)
end

_M.sleep = sleep

function _M.randomseed()
    math.randomseed(ngx.now() * 1000 + ngx.worker.pid())
end

function _M.ip2long(ip)
    local ips = str.split(ip, "\\.")
    local num = 0
    for i = 1, #(ips) do
        num = num + (tonumber(ips[i]) or 0) % 256 * math.pow(256, (4 - i))
    end
    return num
end

function _M.randomint(ip, len)
    local rs = ""
    local longip = _M.ip2long(ip)
    math.randomseed(tostring(ngx.now() * 1000 + longip):reverse():sub(1, 7))
    for i = 1, len do
        local index = math.floor(math.random() * 10)
        rs = rs .. tostring(index)
    end
    return rs
end

function _M.randomstring(ip, len)
    local rs = ""
    local possible = "abcdefghijklmnopqrstuvwxyz0123456789"
    local longip = _M.ip2long(ip)
    math.randomseed(tostring(ngx.now() * 1000 + longip):reverse():sub(1, 7))
    for i = 1, len do
        local index = math.floor(math.random() * string.len(possible)) + 1
        rs = rs .. string.sub(possible, index, index)
    end
    return rs
end

function _M.isIpFormat(ip)
    ip = ip or ''
    local arr = {
        string.match(ip, "^(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)$")
    }
    return #arr == 4
end

function _M.toBase64(source_str)
    local b64chars =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local s64 = ""
    local str = source_str

    while #str > 0 do
        local bytes_num, buf = 0, 0
        for byte_cnt = 1, 3 do
            buf = (buf * 256)
            if #str > 0 then
                buf = buf + string.byte(str, 1, 1)
                str = string.sub(str, 2)
                bytes_num = bytes_num + 1
            end
        end

        for group_cnt = 1, (bytes_num + 1) do
            local b64char = math.fmod(math.floor(buf / 262144), 64) + 1
            s64 = s64 .. string.sub(b64chars, b64char, b64char)
            buf = buf * 64
        end

        for fill_cnt = 1, (3 - bytes_num) do
            s64 = s64 .. "="
        end
    end

    return s64
end

return _M
