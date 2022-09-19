local str = require('man.core.string')
local call_func = require('man.core.utils').call_func
local request = require('man.core.request')
local response = require('man.core.response')
local context = require('man.core.context')
local manager = require('man.config.manager')

local _M = { priority = 19000, name = "proxy-rewrite" }

function _M.rewrite(ctx)
    local conf = ctx.matched_router.rewrite
    if not conf then
        return
    end
    local c = conf
    if conf.conditions then
        for _, condition in ipairs(conf.conditions) do
            if context.is_req_in_allow_list(ctx, condition.allow) then
                c = condition
            end
        end
    end
    ctx._rewrite_conf = c
    if c.force_https then
        if ctx.var.scheme == 'http' then
            response.redirect('https://' .. ctx.var.host ..
                ctx.var.request_uri, 301, 'only accept https')
        end
    end
    if c.redirect_uris then
        local upstream_uri = ctx.var.request_uri
        for _, v in ipairs(c.redirect_uris) do
            local m = str.re_matchs(upstream_uri, v.match, 'sijo')
            if m then
                upstream_uri = v.to
                for i, mv in ipairs(m) do
                    upstream_uri = str.re_gsub(upstream_uri,
                        '\\$' .. tostring(i), mv, 'sijo')
                end
                response.redirect(upstream_uri, v.status, v.content)
                return
            end
        end
    end
    if c.req_rewrite_regexp_uri ~= nil then
        local upstream_uri = ctx.var.request_uri
        local uri = str.re_gsub(upstream_uri, c.req_rewrite_regexp_uri[1],
            c.req_rewrite_regexp_uri[2], 'sijo')
        upstream_uri = uri
        request.set_var(ctx, 'upstream_uri', upstream_uri)
    end

    call_func(c.func, ctx)
    _M.set_req_header(ctx, manager.get_custom_configs('global_rewrite'))
    _M.set_req_header(ctx, c)
end

function _M.header_filter(ctx)
    _M.set_response_header(ctx, manager.get_custom_configs('global_rewrite'))
    _M.set_response_header(ctx, ctx._rewrite_conf)
end

function _M.set_req_header(ctx, conf)
    if not conf then
        return
    end

    if conf.requestHeaders ~= nil then
        for _, h in ipairs(conf.requestHeaders) do
            local var
            if h.matchType == 'const' then
                var = h.value
            else
                var = context.get_req_var(ctx, h.value, h.matchType)
            end
            request.set_header(ctx, h.header, var)
        end
    end

    if conf.vars ~= nil then
        for _, h in ipairs(conf.vars) do
            local var
            if h.matchType == 'const' then
                var = h.value
            else
                var = context.get_req_var(ctx, h.value, h.matchType)
            end
            request.set_var(ctx, h.key, var)
        end
    end
end

function _M.set_response_header(ctx, conf)
    if not conf then
        return
    end
    if conf.responseHeaders then
        for _, h in ipairs(conf.responseHeaders) do
            local var
            if h.matchType == 'const' then
                var = h.value
            else
                var = context.get_req_var(ctx, h.value, h.matchType)
            end
            response.set_header(h.header, var)
        end
    end
end

return _M
