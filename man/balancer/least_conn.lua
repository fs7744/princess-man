local binaryHeap = require("binaryheap")

local function least_score(a, b)
    return a.score < b.score
end

local _M = {}

function _M.init(upstream_conf)
    local checker = upstream_conf.checker
    local servers_heap = binaryHeap.minUnique(least_score)
    local o_nodes = upstream_conf.nodes
    local safe_limit = #o_nodes
    for _, v in ipairs(o_nodes) do
        local weight = v.weight or 1
        local score = 1 / weight
        servers_heap:insert({
            server = v,
            effect_weight = 1 / weight,
            score = score
        }, v)
    end

    if checker then
        return {
            find = function(ctx)
                local err, ok, server, info
                for i = 1, safe_limit do
                    server, info = servers_heap:peek()
                    if server == nil then
                        return nil, 'all node picked'
                    end
                    ok, err = checker:get_target_status(server.host,
                        server.port, server.hostname)
                    if ok then
                        info.score = info.score + info.effect_weight
                        servers_heap:update(server, info)
                        return server
                    else
                        info.score = info.score + info.effect_weight * 100
                        servers_heap:update(server, info)
                    end
                end
                return nil, err
            end
        }
    else
        return {
            find = function(ctx)
                local server, info = servers_heap:peek()
                info.score = info.score + info.effect_weight
                servers_heap:update(server, info)
                return server
            end
        }
    end
end

return _M
