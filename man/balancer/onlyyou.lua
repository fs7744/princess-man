local _M = {}

function _M.find(ctx)
    return nil
end

function _M.init(upstream_conf)
    local nodes = upstream_conf.nodes
    local picker = nil
    if nodes then
        local count = #nodes
        if count == 1 then
            local node = nodes[1]
            picker = {
                find = function(ctx)
                    return node
                end
            }
        elseif count == 0 then
            picker = _M
        end
    end
    return picker
end

return _M
