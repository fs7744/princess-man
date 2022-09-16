local chash = require("resty.chash")

local _M = {}

local function fetch_hash_key(ctx, upstream)
    local key = upstream.hash_key or "remote_addr"
    local hash_on = upstream.hash_on or "vars"
    local chash_key

    if hash_on == "vars" then
        chash_key = ctx.var[key]
    elseif hash_on == "header" then
        chash_key = ctx.var["http_" .. key]
    elseif hash_on == "cookie" then
        chash_key = ctx.var["cookie_" .. key]
    elseif hash_on == "ctx" then
        chash_key = ctx[key]
    end

    if not chash_key then
        chash_key = ctx.var["remote_addr"]
    end

    return chash_key
end

function _M.init(upstream_conf)
    local checker = upstream_conf.checker
    local o_nodes = upstream_conf.nodes
    local nodes = {}
    local nodes_hash = {}
    local safe_limit = #upstream_conf.nodes
    for _, v in ipairs(o_nodes) do
        nodes[v.server] = v.weight
        nodes_hash[v.server] = v
    end
    local picker = chash:new(nodes)
    return {
        find = function(ctx)
            local chash_key = fetch_hash_key(ctx, upstream_conf)
            local id, server, last_server_index, ok, err
            id, last_server_index = picker:find(chash_key)
            server = nodes_hash[id]
            if checker then
                ok, err = checker:get_target_status(server.host, server.port,
                    server.hostname)
                if ok then
                    return server
                end

                for i = 2, safe_limit do
                    id, last_server_index = picker:next(last_server_index)
                    server = nodes_hash[id]
                    ok, err = checker:get_target_status(server.host,
                        server.port, server.hostname)
                    if ok then
                        return server
                    end
                end

                return nil, err
            else
                return server
            end
        end
    }
end

return _M
