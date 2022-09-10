local ngx_re = require("ngx.re")
local ffi = require("ffi")
local C = ffi.C
local ffi_cast = ffi.cast
local ffi_new = ffi.new
local ffi_str = ffi.string
local str_type = ffi.typeof("uint8_t[?]")
local base = require("resty.core.base")
local get_string_buf = base.get_string_buf
local ngx_escape_uri = ngx.escape_uri

ffi.cdef [[
    typedef unsigned char u_char;

    int memcmp(const void *s1, const void *s2, size_t n);

    u_char * ngx_hex_dump(u_char *dst, const u_char *src, size_t len);

    int RAND_bytes(unsigned char *buf, int num);

    int RAND_pseudo_bytes(unsigned char *buf, int num);
]]

local _M = {}

setmetatable(_M, { __index = string })

function _M.has_prefix(s, prefix)
    if type(s) ~= "string" or type(prefix) ~= "string" then
        error("unexpected type: s:" .. type(s) .. ", prefix:" .. type(prefix))
    end
    if #s < #prefix then
        return false
    end
    local rc = C.memcmp(s, prefix, #prefix)
    return rc == 0
end

function _M.has_suffix(s, suffix)
    if type(s) ~= "string" or type(suffix) ~= "string" then
        error("unexpected type: s:" .. type(s) .. ", suffix:" .. type(suffix))
    end
    if #s < #suffix then
        return false
    end
    local rc = C.memcmp(ffi_cast("char *", s) + #s - #suffix, suffix, #suffix)
    return rc == 0
end

function _M.split(s, p, max, options, ctx, res)
    return ngx_re.split(s, p, options, ctx, max, res)
end

function _M.re_gsub(subject, regex, replace, options)
    return ngx.re.gsub(subject, regex, replace, options)
end

function _M.find(s, pattern, from)
    return string.find(s, pattern, from or 1, true)
end

function _M.contains(s, pattern, from)
    return _M.find(s, pattern, from) ~= nil
end

function _M.re_find(subject, regex, options, ctx, nth)
    return ngx.re.find(subject, regex, options, ctx, nth)
end

function _M.re_match(subject, regex, options, ctx, nth)
    local from, to = ngx.re.find(subject, regex, options, ctx, nth)
    if from then
        return string.sub(subject, from, to)
    end
    return nil
end

function _M.re_matchs(subject, regex, options)
    return ngx.re.match(subject, regex, options)
end

function _M.r_pad(s, l, c)
    return s .. string.rep(c or ' ', l - #s)
end

function _M.from_hex(str)
    return (str:gsub('..', function(cc)
        return string.char(tonumber(cc, 16))
    end))
end

function _M.to_hex(s)
    local len = #s
    local buf_len = len * 2
    local buf = ffi_new(str_type, buf_len)
    C.ngx_hex_dump(buf, s, len)
    return ffi_str(buf, buf_len)
end

local match_operators = {
    startwith = function(s, v)
        return _M.has_prefix(s, v)
    end,
    equal = function(s, v)
        return s == v
    end,
    regexp = function(s, v)
        return ngx.re.find(s, v, 'sijo') ~= nil
    end,
    contains = function(s, v)
        return _M.contains(s, v)
    end
}

function _M.match_by(s, operator, v)
    local op = match_operators[operator or '']
    if not s or not op or not v then
        return false
    end

    return op(s, v)
end

function _M.uri_safe_encode(uri)
    if not uri then
        return uri
    end
    return ngx_escape_uri(uri)
end

function _M.find_last(s, needle)
    if not s then
        return nil
    end
    local i = s:match(".*" .. needle .. "()")
    return i
end

function _M.get_last_sub(path, regex)
    local i = _M.find_last(path, regex)
    if i then
        return string.sub(path, i)
    end
    return nil
end

function _M.get_file_ext(path)
    local p = _M.get_last_sub(path, '/')
    if not p then
        p = path
    end
    local r = _M.get_last_sub(p, '%.')
    if r then
        return string.lower(r)
    end
    return r
end

function _M.rand_bytes(len, strong)
    local buf = ffi_new("char[?]", len)
    if strong then
        if C.RAND_bytes(buf, len) == 0 then
            return nil
        end
    else
        C.RAND_pseudo_bytes(buf, len)
    end

    return ffi_str(buf, len)
end

function _M.trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

return _M
