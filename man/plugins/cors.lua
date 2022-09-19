local str = require('man.core.string')
local request = require('man.core.request')
local response = require('man.core.response')
local manager = require('man.config.manager')

local _M = { priority = 20000, name = "cors" }

local function match_origin(ctx, cors)
    local allow_origin = cors.allow_origin
    if allow_origin == '*' then
        return allow_origin
    end
    local req_origin = request.get_header(ctx, "Origin")
    if allow_origin == req_origin then
        return allow_origin
    end
    local allow_origins = cors.allow_origins
    if allow_origins and allow_origins[req_origin] then
        return req_origin
    end
    local allow_origin_regex = cors.allow_origin_regex
    if allow_origin_regex and str.re_find(req_origin, allow_origin_regex, 'sijo') then
        return req_origin
    end
    return nil
end

function _M.rewrite(ctx)
    if not ctx.matched_router.cors or not manager.get_custom_configs('global_cors') then
        return
    end
    if ctx.var.method == "OPTIONS" then
        return response.exit(200)
    end
end

function _M.header_filter(ctx)
    local cors = ctx.matched_router.cors
    if not cors then
        cors = manager.get_custom_configs('global_cors')
    end
    if not cors then
        return
    end
    local origin = match_origin(ctx, cors)
    if origin then
        response.set_header("Access-Control-Allow-Origin", origin)
        if not (ctx.var.method == "OPTIONS" or ctx.var.method == "GET") then
            return
        end
        if origin ~= "*" then
            response.add_header("Vary", "Origin")
        end
        if cors.allow_headers == nil then
            response.set_header("Access-Control-Allow-Headers",
                request.get_header(ctx,
                    'Access-Control-Request-Headers'))
        else
            response.set_header("Access-Control-Allow-Headers",
                cors.allow_headers)
        end
        if cors.allow_methods == nil then
            response.set_header("Access-Control-Allow-Methods",
                request.get_header(ctx,
                    'Access-Control-Request-Method'))
        else
            response.set_header("Access-Control-Allow-Methods",
                cors.allow_methods)
        end
        response.set_header("Access-Control-Max-Age", cors.max_age)
        response.set_header("Access-Control-Expose-Headers", cors.expose_headers)
        if cors.allow_credential then
            response.set_header("Access-Control-Allow-Credentials", true)
        end
    end
end

return _M
