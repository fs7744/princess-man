local _M = { priority = 19999, name = "websocket" }

function _M.rewrite(ctx)
    if ctx.matched_router.websocket and ctx.var.http_upgrade then
        ngx.var.upstream_upgrade = ctx.var.http_upgrade
        ngx.var.upstream_connection = 'Upgrade'
    end
end

return _M
