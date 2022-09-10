local table_clear = require("man.core.table").clear
local table_pool_fetch = require("man.core.table").pool_fetch
local table_pool_release = require("man.core.table").pool_release
local ctxdump = require("resty.ctxdump")
local get_var = require("resty.ngxvar").fetch
local get_request = require("resty.ngxvar").request
local ngx = ngx
local ngx_var = ngx.var

local _M = {}

do

    local mt = {
        __index = function(t, key)
            local cached = t._cache[key]
            if cached ~= nil then
                return cached
            end

            if type(key) ~= "string" then
                error("invalid argument, expect string value", 2)
            end

            local val = get_var(key, t._request)

            if val ~= nil then
                t._cache[key] = val
            end

            return val
        end,

        __newindex = function(t, key, val)
            t._cache[key] = val
            ngx_var[key] = val
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

    function _M.release_vars(ctx)
        if ctx.var == nil then
            return
        end

        table_clear(ctx.var._cache)
        table_pool_release("ctx_var", ctx.var, true)
        ctx.var = nil
    end

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

return _M
