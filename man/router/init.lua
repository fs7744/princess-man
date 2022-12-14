local config = require("man.config.manager")
local sni = require("man.router.sni")
local l4 = require("man.router.l4")
local l7 = require("man.router.l7")
local tb = require('man.core.table')
local events = require("man.core.events")
local radix = require("resty.radixtree")
local up = require('man.balancer.upstream')

local _M = { _destroy = { up.destroy_router } }

local function update(routers, m, unload)
    local old_router = m.router
    local old = tb.new(32, 0)
    for key, value in pairs(unload or {}) do
        if m.current[key] then
            tb.insert(old, m.current[key])
            m.current[key] = nil
        end
    end
    for key, value in pairs(routers or {}) do
        if m.current[key] then
            tb.insert(old, m.current[key])
            m.current[key] = nil
        end
        if m.filter(value) then
            value.id = key
            _, m.current[key] = pcall(m.init_router_metadata, value)
        end
    end
    local rs = tb.new(#m.current, 0)
    for _, rc in pairs(m.current) do
        table.insert(rs, rc)
    end
    m.router = radix.new(rs)
    for _, o in ipairs(old) do
        for i, value in ipairs(_M._destroy) do
            pcall(value, o)
        end
        tb.clear(o)
    end
    tb.clear(old)
    if old_router then
        old_router:free()
    end
end

function _M.init_worker()
    up.init(config.get_config('params'))
    local routers = config.get_config('router')
    if require('man.core.ngp').is_http_system() then
        update(routers.l7, l7)
    else
        update(routers.sni, sni)
        update(routers.l4, l4)
    end

    events.register('router_l4', function(rs)
        update(rs.load, l4, rs.unload)
    end)
    events.register('router_sni', function(rs)
        update(rs.load, sni, rs.unload)
    end)
    events.register('router_l7', function(rs)
        update(rs.load, l7, rs.unload)
    end)
end

return _M
