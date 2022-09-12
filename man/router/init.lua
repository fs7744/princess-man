local config = require("man.config.manager")
local sni = require("man.router.sni")
local l4 = require("man.router.l4")
local l7 = require("man.router.l7")
local tb = require('man.core.table')
local events = require("man.core.events")
local radix = require("resty.radixtree")
local log = require("man.core.log")
local lock = require("man.core.lock")

local _M = {}

local function update(routers, m)
    local old_router = m.router
    local old = tb.new(32, 0)
    for key, value in pairs(routers or {}) do
        if m.current[key] then
            tb.insert(old, m.current[key])
            m.current[key] = nil
        end
        if m.filter(value) then
            value.id = key
            m.current[key] = m.init_router_metadata(value)
        end
    end
    local rs = tb.new(#m.current, 0)
    for _, rc in pairs(m.current) do
        table.insert(rs, rc)
    end
    m.router = radix.new(rs)
    for _, o in ipairs(old) do
        if _M._destroy then
            for key, value in pairs(_M._destroy) do
                value(o)
            end
        end
        tb.clear(o)
    end
    tb.clear(old)
    if old_router then
        old_router:free()
    end
end

local function update_routers()

end

function _M.init_worker()
    --events.register("config_change", update_routers)
    local routers = config.get_config('router')
    update(routers.sni, sni)
    update(routers.l4, l4)
    update(routers.l7, l7)
end

return _M
