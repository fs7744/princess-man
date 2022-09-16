local log = require("man.core.log")
local tablelib = require("man.core.table")
local resty_lock = require("resty.lock")
local ngx_now = ngx.now
local shm_ewma = ngx.shared["balancer-ewma"]
local shm_last_touched_at = ngx.shared["balancer-ewma-last-touched-at"]
local decay_time = 10 -- seconds
local lock, err = resty_lock:new("lrucache_lock")

local _M = {}

local function decay_ewma(ewma, last_touched_at, rtt, now)
    local td = now - last_touched_at
    td = math.max(td, 0)
    local weight = math.exp(-td / decay_time)

    ewma = ewma * weight + rtt * (1.0 - weight)
    return ewma
end

local function get_ewma(server, rtt)
    local ewma = shm_ewma:get(server) or 0
    local now = ngx_now()
    local last_touched_at = shm_last_touched_at:get(server) or 0
    return decay_ewma(ewma, last_touched_at, rtt, now)
end

-- for test
_M.get_ewma = get_ewma

local function p2c(nodes, ctx)
    local remaining_nodes = ctx._remaining_nodes
    if not remaining_nodes then
        remaining_nodes = tablelib.pool_fetch("remaining_nodes", 0, 2)
        for _, v in ipairs(nodes) do
            tablelib.insert(remaining_nodes, v)
        end
        ctx._remaining_nodes = remaining_nodes
    end
    local count = #remaining_nodes
    local node_i
    if count > 1 then
        local node_j
        local i, j = math.random(1, count), math.random(1, count - 1)
        if j >= i then
            j = j + 1
        end

        node_i, node_j = remaining_nodes[i], remaining_nodes[j]
        if get_ewma(node_i.server, 0) > get_ewma(node_j.server, 0) then
            node_i = node_j
            i = j
        end
        tablelib.remove(remaining_nodes, i)
    elseif count == 1 then
        node_i = tablelib.remove(remaining_nodes, 1)
    end

    return node_i
end

local function update_ewma(server, rtt)
    local now = ngx_now()
    local ewma = get_ewma(server, rtt)
    local success, err, forcible = shm_last_touched_at:set(server, now)
    if not success then
        log.error("shm_last_touched_at:set failed: ", err)
    end
    if forcible then
        log.warn("shm_last_touched_at:set valid items forcibly overwritten")
    end

    success, err, forcible = shm_ewma:set(server, ewma)
    if not success then
        log.error("shm_ewma:set failed: ", err)
    end
    if forcible then
        log.warn("shm_ewma:set valid items forcibly overwritten")
    end
end

local function after_balance(ctx)
    if ctx._remaining_nodes then
        tablelib.pool_release("remaining_nodes", ctx._remaining_nodes)
        ctx._remaining_nodes = nil
    end
    if ctx.proxy_server then
        local response_time = ctx.var.upstream_response_time or 0
        local connect_time = ctx.var.upstream_connect_time or 0
        local rtt = connect_time + response_time
        local s = ctx.proxy_server.server

        local elapsed
        elapsed, err = lock:lock(s .. ":ewma")
        if not elapsed then
            return nil, err
        end

        local r
        r, err = update_ewma(s, rtt)
        local ok, lock_err = lock:unlock()
        if not ok then
            return nil, lock_err
        end
    end
end

function _M.init(upstream_conf)
    local nodes = upstream_conf.nodes
    local nodes_count = #nodes
    local checker = upstream_conf.checker
    if checker then
        return {
            after_balance = after_balance,
            find = function(ctx)
                local server, ok, err
                for i = 1, nodes_count do
                    server = p2c(nodes, ctx)
                    ok, err = checker:get_target_status(server.host,
                        server.port, server.hostname)
                    if ok then
                        return server
                    end
                end
                return nil, err
            end
        }
    else
        return {
            after_balance = after_balance,
            find = function(ctx)
                return p2c(nodes, ctx)
            end
        }
    end
end

return _M
