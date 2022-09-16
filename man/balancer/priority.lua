local log = require('man.core.log')

local _M = {}

local function upstream_filter(ctx, upstream_conf)
    if upstream_conf and upstream_conf.filter and upstream_conf.filter.plugin then
        local filter, _, err
        _, filter, err = pcall(require, upstream_conf.filter.plugin)
        if filter and filter.upstream_filter then
            return filter.upstream_filter(ctx, upstream_conf)
        end
        log.error(upstream_conf.filter.plugin, 'load failed: ', err)
        return false
    end
    return true
end

local function try_next_upstream(ctx, nodeTriedCount)
    local upstream = ctx._upstream
    if upstream and nodeTriedCount <= #upstream.nodes then
        return upstream, nodeTriedCount
    end

    upstream = nil
    local i = ctx._upstreamId or 1
    local upstreams = ctx.router_conf.upstreams
    local err
    local count = #upstreams
    while i <= count do
        local upstream_conf = upstreams[i]
        i = i + 1
        if upstream_conf and upstream_filter(ctx, upstream_conf) then
            upstream = upstream_conf
            goto done
        end
    end
    ::done::
    ctx._upstreamId = i
    ctx._upstream = upstream
    return upstream, 1, err
end

function _M.pick_server(ctx)
    local node, temp, upstream, err
    local nodeTriedCount = ctx._triedCount or 1
    upstream, nodeTriedCount, err = try_next_upstream(ctx, nodeTriedCount)
    while upstream and upstream.picker and node == nil do
        local count = #upstream.nodes
        if count == 0 then
            ctx._upstream = nil
            upstream, nodeTriedCount, err = try_next_upstream(ctx)
            goto next
        end
        if nodeTriedCount <= count then
            nodeTriedCount = nodeTriedCount + 1
            temp, err = upstream.picker.find(ctx)
            if temp then
                node = temp
            else
                ctx._upstream = nil
                upstream, nodeTriedCount, err = try_next_upstream(ctx)
            end
        end
        ::next::
    end

    ctx._triedCount = nodeTriedCount
    return node, err
end

return _M
