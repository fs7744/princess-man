local roundrobin = require("resty.roundrobin")

local _M = {}

function _M.init(upstream_conf)
    local checker = upstream_conf.checker
    local o_nodes = upstream_conf.nodes
    local nodes = {}
    local nodes_hash = {}
    local safe_limit = #upstream_conf.nodes
    for _, v in ipairs(o_nodes) do
        nodes[v.server] = v.weight + 1
        nodes_hash[v.server] = v
    end
    local picker = roundrobin:new(nodes)
    return {
        find = function(ctx)
            local node, err, ok, server
            for i = 1, safe_limit do
                node, err = picker:find()
                if not node then
                    return nil, err
                end
                server = nodes_hash[node]
                if checker then
                    ok, err = checker:get_target_status(server.host,
                        server.port, server.hostname)
                    if ok then
                        return server
                    end
                else
                    return server
                end
            end
            return nil, err
        end
    }
end

return _M
