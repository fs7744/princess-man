local jwt = require("resty.jwt")
local log = require('man.core.log')
local json = require('man.core.json')
local request = require('man.core.request')
local response = require('man.core.response')

local _M = { priority = 9000, name = "jwt-auth" }

local function no_need_jwt_verify(ctx, conf)
    local plugin = conf.bypass_plugin
    local p, _
    if plugin then
        _, p = pcall(require, plugin)
    end
    if p and p.jwt_bypass then
        return p.jwt_bypass(ctx, conf)
    end
    return false
end

local function get_jwt_token(ctx, conf)
    local r
    if conf.from_header then
        for _, v in ipairs(conf.from_header) do
            r = ctx.var["http_" .. v]
            if r then
                return r
            end
        end
    end

    if conf.from_query_string then
        local args = request.get_uri_args(ctx)
        for _, v in ipairs(conf.from_query_string) do
            r = args[v]
            if r then
                return r
            end
        end
    end

    if conf.from_cookie then
        for _, v in ipairs(conf.from_cookie) do
            r = ctx.var["cookie_" .. v]
            if r then
                return r
            end
        end
    end

    if conf.from_plugin then
        local _, p = pcall(require, conf.from_plugin)
        if p and p.get_jwt_token then
            return p.get_jwt_token(ctx, conf)
        end
    end

    return r
end

function _M.rewrite(ctx)
    local conf = ctx.matched_router.jwt_auth
    if not conf or no_need_jwt_verify(ctx, conf) then
        return
    end
    log.info("call jwt-auth in rewrite")
    local jwt_token = get_jwt_token(ctx, conf)
    if not jwt_token then
        return response.exit(401, json.encode({ message = "Missing jwt token." }))
    end
    local jwt_obj = jwt:verify(conf.secret, jwt_token)
    if not jwt_obj.valid then
        return response.exit(401, json.encode({ message = jwt_obj.reason }))
    end
    ctx.jwt_token = jwt_obj
end

return _M
