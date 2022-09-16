local healthcheck = require('resty.healthcheck')
local onlyyou = require('man.balancer.onlyyou')
local dns = require("man.balancer.dns.client")
local log = require("man.core.log")
require("lfs")
require 'pl.compat'

local _M = {}

local function create_picker(upstream_conf)
    local picker, err = onlyyou.init(upstream_conf)
    if picker == nil then
        local picker_creater, _
        _, picker_creater, err = pcall(require,
            'man.balancer.' .. upstream_conf.lb)
        if picker_creater then
            picker, err = picker_creater.init(upstream_conf)
        end
    end
    upstream_conf.picker = picker
    return picker, err
end

local function clean_upstream_conf(upstream_conf)
    if upstream_conf then
        if upstream_conf.checker then
            if upstream_conf.checker.destroy then
                upstream_conf.checker.destroy()
            end
            upstream_conf.checker = nil
        end
        if upstream_conf.picker then
            if upstream_conf.picker.destroy then
                upstream_conf.picker.destroy()
            end
            upstream_conf.picker = nil
        end
    end
end

local function fetch_domain(upstream_conf)
    if not _M.dns then
        return
    end
    local nodes = table.new(#upstream_conf.nodes, 0)
    for _, node in ipairs(upstream_conf.nodes) do
        if node.domain then
            local hosts, err = _M.dns:resolve(node.host, _M.dns.RETURN_ALL)
            if hosts then
                for _, host in ipairs(hosts) do
                    local newNode = {
                        server = node.server .. host.address .. node.port,
                        host = host.address,
                        port = node.port,
                        weight = node.weight,
                        rewrite = node.rewrite,
                        pool = host.address .. ':' .. node.port
                    }
                    newNode.proxy_host = string.lower(node.host)
                    newNode.hostname = newNode.proxy_host
                    table.insert(nodes, newNode)
                end
            else
                log.error(node.host, " dns resolve failed: ", err)
            end
        else
            node.hostname = node.host
            node.pool = node.host .. ':' .. node.port
            table.insert(nodes, node)
        end
    end
    upstream_conf.nodes = nodes
end

local function create_checker(upstream_conf, id)
    local checker
    if upstream_conf.healthcheck and #upstream_conf.nodes > 1 then
        checker = healthcheck.new({
            name = id .. 'healthcheck',
            shm_name = "healthcheck",
            events_module = 'resty.events',
            checks = upstream_conf.healthcheck
        })
        upstream_conf.checker = checker
        for _, node in ipairs(upstream_conf.nodes) do
            local hostname = node.hostname
            local ok, err = checker:add_target(node.host, node.port, hostname)
            checker.targets[node.host] = checker.targets[node.port] or {}
            checker.targets[node.host][node.port] = checker.targets[node.host][node.port] or {}
            checker.targets[node.host][node.port][hostname] = {
                ip = node.host,
                port = node,
                hostname = hostname,
                hostheader = nil,
                internal_health = "healthy"
            }
            if not ok then
                log.error("failed to add new health check target: ", node.host,
                    ":", node.port, " err: ", err)
            end
        end
        checker.destroy = function()
            checker:clear()
            checker:stop()
        end
    end
    return checker
end

function _M.init(opts)
    -- opts.order = { "last", "A", "AAAA", "CNAME" }
    -- opts.search = {}
    _M.dns = dns.new(opts.dns)
end

function _M.init_router(router_id, router_conf)
    for _, p in ipairs(router_conf.upstreams) do
        fetch_domain(p)
        create_checker(p, router_id)
        create_picker(p)
    end
end

function _M.destroy_router(router_conf)
    for _, p in ipairs(router_conf.upstreams) do
        clean_upstream_conf(p)
    end
end

return _M
