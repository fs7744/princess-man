local ffi = require("ffi")
local ffi_str = ffi.string
local ffi_errno = ffi.errno
local C = ffi.C
local tostring = tostring
local type = type

local _M = {}
local WNOHANG = 1

ffi.cdef [[
    typedef int32_t pid_t;
    typedef unsigned int  useconds_t;

    int setenv(const char *name, const char *value, int overwrite);
    char *strerror(int errnum);

    int usleep(useconds_t usec);
    pid_t waitpid(pid_t pid, int *wstatus, int options);
]]

local function err()
    return ffi_str(C.strerror(ffi_errno()))
end

function _M.osname()
    return ffi.os
end

function _M.setenv(name, value)
    local tv = type(value)
    if type(name) ~= "string" or (tv ~= "string" and tv ~= "number") then
        return false, "invalid argument"
    end

    value = tostring(value)
    local ok = C.setenv(name, value, 1) == 0
    if not ok then
        return false, err()
    end
    return true
end

local function waitpid_nohang(pid)
    local res = C.waitpid(pid, nil, WNOHANG)
    if res == -1 then
        return nil, err()
    end
    return res > 0
end

function _M.waitpid(pid, timeout)
    local count = 0
    local step = 1000 * 10
    local total = timeout * 1000 * 1000
    while step * count < total do
        count = count + 1
        C.usleep(step)
        local ok, err = waitpid_nohang(pid)
        if err then
            return nil, err
        end
        if ok then
            return true
        end
    end
end

return _M
