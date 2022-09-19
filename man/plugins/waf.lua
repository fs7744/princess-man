local manager = require('man.config.manager')
local str = require('man.core.string')
local response = require('man.core.response')
local request = require('man.core.request')
local log = require('man.core.log')
local rf = str.re_find
local unescape = ngx.unescape_uri

local _M = { priority = 20500, name = "waf" }

local function create_var_check(var_name)
    return function(ctx, rules)
        local data = ctx.var[var_name]
        if data ~= nil then
            for i, rule in ipairs(rules) do
                if rule ~= "" and rf(data, rule, "sijo") then
                    request.set_var(ctx, 'reason', 'waf: ' .. var_name .. i)
                    return false
                end
            end
        end
        return true
    end
end

local function try_waf(ctx, conf)
    if not conf then
        return
    end
    local allow = true
    local c
    for _, checker in ipairs(conf.checkers) do
        c = _M[checker.op]
        if allow then
            if c then
                allow = c(ctx, checker.rules, checker.rules_for_key)
            elseif str.has_prefix(checker.op, 'http_') then
                c = create_var_check(checker.op)
                _M[checker.op] = c
                allow = c(ctx, checker.rules, checker.rules_for_key)
            end
        else
            break
        end
    end

    if allow and conf.all_headers_checker then
        allow = _M.all_headers_check(ctx, conf.all_headers_checker)
    end
    if allow and conf.body_checker then
        allow = _M.body_check(ctx, conf.body_checker)
    end

    if not allow then
        response.exit(400)
    end
end

function _M.args(ctx, rules, rules_for_key)
    local args = request.get_uri_args(ctx)
    for k, val in pairs(args) do
        local args_data
        if type(val) == 'table' then
            local t = {}
            for _, v in pairs(val) do
                if v == true then
                    v = ""
                end
                table.insert(t, v)
            end
            args_data = table.concat(t, " ")
        else
            args_data = val
        end
        if args_data and type(args_data) ~= "boolean" then
            for i, rule in ipairs(rules) do
                if rule ~= "" and rf(unescape(args_data), rule, "sijo") then
                    request.set_var(ctx, 'reason', 'waf: args' .. i)
                    return false
                end
            end
        end
        for i, rule in ipairs(rules_for_key) do
            if rule ~= "" and rf(unescape(k), rule, "sijo") then
                request.set_var(ctx, 'reason', 'waf: args for key' .. i)
                return false
            end
        end
    end

    return true
end

_M.user_agent = create_var_check('http_user_agent')
_M.cookie = create_var_check('http_cookie')
_M.uri = create_var_check('uri')

function _M.body_check(ctx, checker)
    if checker.method and not checker.method[ctx.var.method] then
        return true
    end
    local max = checker.max_content_length or 10000
    if tonumber(ctx.var.http_content_length or 0) > max then
        return true
    end
    local content_type = str.lower(ctx.var.http_content_type or '')
    content_type = str.split(content_type, ' |;', 2)[1]
    if checker.content_type and not checker.content_type[content_type] then
        return true
    end
    local body, err = request.get_body(ctx)
    if body then
        for i, rule in ipairs(checker.rules) do
            if rule ~= "" and rf(body, rule, "sijo") then
                request.set_var(ctx, 'reason', 'waf: body ' .. content_type .. i)
                return false
            end
        end
    elseif err then
        log.error('waf get request body err: ', err)
    end
    return true
end

function _M.all_headers_check(ctx, checker)
    for key, value in pairs(request.headers(ctx)) do
        for i, rule in ipairs(checker.rules) do
            if rule ~= "" and rf(value, rule, "sijo") then
                request.set_var(ctx, 'reason',
                    'waf: headers ' .. i .. ' ' .. key .. ':' ..
                    value)
                return false
            end
        end
        for i, rule in ipairs(checker.rules_for_key) do
            if rule ~= "" and rf(key, rule, "sijo") then
                request.set_var(ctx, 'reason',
                    'waf: headers for key' .. i .. ' ' .. key .. ':' ..
                    value)
                return false
            end
        end
    end
    return true
end

function _M.rewrite(ctx)
    local waf = ctx.matched_router.waf
    if not waf or waf.no_global ~= true then
        try_waf(ctx, manager.get_custom_configs('global_waf'))
    end
    if not ctx._stop then
        try_waf(ctx, ctx.matched_router.waf)
    end
end

return _M
