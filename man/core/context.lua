local table_clear = require("man.core.table").clear
local table_pool_fetch = require("man.core.table").pool_fetch
local table_pool_release = require("man.core.table").pool_release
local ctxdump = require("resty.ctxdump")
local str = require("man.core.string")
local log = require("man.core.log")
local env = require("resty.env")
local cookie = require("resty.cookie")
local get_var = require("resty.ngxvar").fetch
local get_request = require("resty.ngxvar").request
local expr = require("resty.expr.v1")
local ngx = ngx
local ngx_var = ngx.var

local _M = {}

local ngx_var_names = {
    upstream_scheme     = true,
    upstream_host       = true,
    upstream_upgrade    = true,
    upstream_connection = true,
    upstream_uri        = true,

    upstream_mirror_host = true,

    upstream_cache_zone      = true,
    upstream_cache_zone_info = true,
    upstream_no_cache        = true,
    upstream_cache_key       = true,
    upstream_cache_bypass    = true,

    proxy_host = true,
}

if require('man.core.ngp').is_http_system() then
    local var_methods = {
        method = ngx.req.get_method,
        cookie = function()
            if ngx.var.http_cookie then
                return cookie:new()
            end
        end
    }

    local mt = {
        __index = function(t, key)
            local cached = t._cache[key]
            if cached ~= nil then
                return cached
            end

            if type(key) ~= "string" then
                error("invalid argument, expect string value", 2)
            end

            local val
            local method = var_methods[key]
            if method then
                val = method()

            elseif str.has_prefix(key, "cookie_") then
                local cookie = t.cookie
                if cookie then
                    local err
                    val, err = cookie:get(str.sub(key, 8))
                    if err then
                        log.warn("failed to fetch cookie value by key: ", key,
                            " error: ", err)
                    end
                end

            elseif str.has_prefix(key, "http_") then
                local k = key:lower()
                k = str.re_gsub(k, "-", "_", "jo")
                val = get_var(k, t._request)
            elseif str.has_prefix(key, "env_") then
                local k = str.re_gsub(key, "env_", "", "jo")
                var_methods[key] = function()
                    return env.get(k)
                end
                val = var_methods[key]()
            elseif str.has_prefix(key, "ctx_") then
                local k = str.re_gsub(key, "ctx_", "", "jo")
                return ngx.ctx.api_ctx[k]
            else
                val = get_var(key, t._request)
            end

            if val ~= nil then
                t._cache[key] = val
            end

            return val
        end,

        __newindex = function(t, key, val)
            t._cache[key] = val
            if ngx_var_names[key] then
                ngx_var[key] = val
            end
        end
    }

    function _M.set_vars_meta(ctx)
        local var = table_pool_fetch("ctx_var", 0, 32)
        if not var._cache then
            var._cache = {}
        end
        var._request = get_request()
        setmetatable(var, mt)
        ctx.var = var
    end
else
    local mt = {
        __index = function(t, key)
            local cached = t._cache[key]
            if cached ~= nil then
                return cached
            end

            if type(key) ~= "string" then
                error("invalid argument, expect string value", 2)
            end

            local val

            if str.has_prefix(key, "env_") then
                local k = str.re_gsub(key, "env_", "", "jo")
                val = env.get(k)
            elseif str.has_prefix(key, "ctx_") then
                local k = str.re_gsub(key, "ctx_", "", "jo")
                return ngx.ctx.api_ctx[k]
            else
                val = get_var(key, t._request)
            end

            if val ~= nil then
                t._cache[key] = val
            end

            return val
        end,

        __newindex = function(t, key, val)
            t._cache[key] = val
            if ngx_var_names[key] then
                ngx_var[key] = val
            end
        end
    }

    function _M.set_vars_meta(ctx)
        local var = table_pool_fetch("ctx_var", 0, 32)
        if not var._cache then
            var._cache = {}
        end
        var._request = get_request()
        setmetatable(var, mt)
        ctx.var = var
    end
end

function _M.release_vars(ctx)
    if ctx.var == nil then
        return
    end

    table_clear(ctx.var._cache)
    table_pool_release("ctx_var", ctx.var, true)
    ctx.var = nil
end

function _M.new_api_context()
    local api_ctx = table_pool_fetch("api_ctx", 0, 32)
    ngx.ctx.api_ctx = api_ctx
    _M.set_vars_meta(api_ctx)
    return api_ctx
end

function _M.get_api_context()
    if ngx.ctx then
        return ngx.ctx.api_ctx
    else
        return nil
    end
end

function _M.clear_api_context()
    local api_ctx = ngx.ctx.api_ctx
    if api_ctx then
        _M.release_vars(api_ctx)
        table_pool_release("api_ctx", api_ctx)
        ngx.ctx.api_ctx = nil
    end
end

function _M.stash()
    local ref = ctxdump.stash_ngx_ctx()
    log.info("stash ngx ctx: ", ref)
    ngx_var.ctx_ref = ref
end

function _M.apply_ctx()
    local ref = ngx_var.ctx_ref
    log.info("apply ngx ctx: ", ref)
    local ctx = ctxdump.apply_ngx_ctx(ref)
    ngx_var.ctx_ref = ''
    ngx.ctx = ctx
    return ctx
end

function _M.register_var_name(key)
    ngx_var_names[key] = true
end

function _M.get_req_var(ctx, key, type)
    local r

    if type == "vars" then
        r = ctx.var[key]
    elseif type == "path" then
        r = ctx.var.uri
    elseif type == "originalUrl" then
        r = ctx.var.request_uri
    elseif type == "header" then
        r = ctx.var["http_" .. key]
    elseif type == "cookie" then
        r = ctx.var["cookie_" .. key]
    elseif type == "env" then
        r = env.get(key)
    elseif type == "ctx" then
        r = ctx[key]
    end

    return r
end

function _M.is_req_in_allow_list(ctx, allowList)
    for _, allow in ipairs(allowList) do
        local ex = allow._expr
        if ex then
            if ex:eval(ctx.var) == true then
                return true
            end
        elseif allow.expr then
            local err
            ex, err = expr.new(allow.expr)
            allow._expr = ex
            if err then
                log.error('is_req_in_allow_list expr failed ', err)
            end
            if ex:eval(ctx.var) == true then
                return true
            end
        elseif allow.matchType then
            local var = _M.get_req_var(ctx, allow.matchKey, allow.matchType)
            if str.match_by(var, allow.operator, allow.value) then
                return true
            end
        end
    end
    return false
end

return _M
