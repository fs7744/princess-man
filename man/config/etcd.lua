local json = require("man.core.json")
local log = require("man.core.log")
local str = require("man.core.string")
local etcdlib = require("resty.etcd")
local events = require("man.core.events")
local exiting = ngx.worker.exiting
local table = require("man.core.table")
local timers = require("man.core.timers")

local _M = { etcd_version = 0 }

local cache = {}
function _M.new_etcd(etcd_conf)
    etcd_conf.protocol = "v3"
    local etcd, err = etcdlib.new(etcd_conf)
    if err ~= nil then
        return nil, err
    end
    _M.etcd_key_prefix = etcd_conf.prefix
    _M.plugin_prefix = etcd_conf.prefix .. '/plugins/'
    _M.router_prefix_l4 = etcd_conf.prefix .. '/router/l4/'
    _M.router_prefix_sni = etcd_conf.prefix .. '/router/sni/'
    _M.router_prefix_l7 = etcd_conf.prefix .. '/router/l7/'
    _M.custom_configs_prefix = etcd_conf.prefix .. '/'
    _M.etcd = etcd
    return etcd
end

function _M.get_config(key)
    return cache[key]
end

local function update_etcd_version(version)
    if not version then
        return
    end
    _M.etcd_version = tonumber(version)
end

function _M.read_all_config()
    local res, err = _M.etcd:readdir('')
    if err ~= nil then
        return nil, err
    end
    log.info("get etcd all config data.")
    update_etcd_version(res.body.header.revision)
    local plugins = {}
    local routes_l4 = {}
    local routes_sni = {}
    local routes_l7 = {}
    if res.body.kvs then
        for _, kv in ipairs(res.body.kvs) do
            if str.has_prefix(kv.key, _M.plugin_prefix) then
                plugins[kv.key] = kv.value
            elseif str.has_prefix(kv.key, _M.router_prefix_l4) then
                routes_l4[str.re_gsub(kv.key, _M.router_prefix_l4, '', 'jo')] = kv.value
            elseif str.has_prefix(kv.key, _M.router_prefix_sni) then
                routes_sni[str.re_gsub(kv.key, _M.router_prefix_sni, '', 'jo')] = kv.value
            elseif str.has_prefix(kv.key, _M.router_prefix_l7) then
                routes_l7[str.re_gsub(kv.key, _M.router_prefix_l7, '', 'jo')] = kv.value
            else
                _M.cache[str.re_gsub(kv.key, _M.custom_configs_prefix, '', 'jo')] = kv.value
            end
        end
    end
    cache.router = { l4 = routes_l4, sni = routes_sni, l7 = routes_l7 }
    cache.plugins = plugins
end

function _M.init(params)
    cache.params = params
    _M.new_etcd(params.etcd_conf)
    _M.read_all_config()
end

local function watch_dir(dir)
    local opts = {
        start_revision = _M.etcd_version + 1,
        timeout = cache.params.etcd_conf.timeout or 300,
        need_cancel = true
    }

    local res_fn, err, cancel = _M.etcd:watchdir(dir, opts)
    if err ~= nil then
        return nil, err
    end
    local res
    res, err = res_fn()
    if not err then
        if not res or not res.result or not res.result.events then
            res, err = res_fn()
        end
    end

    if cancel then
        local res_cancel, err_cancel = _M.etcd:watchcancel(cancel)
        if res_cancel == 1 then
            log.info("Cancel etcd watch connection success")
        else
            log.error("Cancel etcd watch failed: ", err_cancel)
        end
    end

    if err ~= nil then
        return nil, err
    end
    return res
end

local function filter_event(key, v, prefix, events_data)
    if str.has_prefix(key, prefix) then
        events_data.has = true
        local vk = str.re_gsub(key, prefix, '', 'jo')
        if v.type == 'DELETE' then
            events_data.unload[vk] = true
        else
            events_data.load[vk] = v.value
        end
        return true
    else
        return false
    end
end

local function publish_event(events_data, key)
    if events_data.has then
        events.publish_all('etcd', key, events_data)
    end
end

local function do_watch_etcd()
    local res, e = watch_dir('')
    if e then
        log.error("Watch etcd failed: ", e)
    end
    if res and res.result then
        update_etcd_version(res.result.header.revision)
        local events_data = res.result.events
        if events_data then
            log.notice('fetch etcd config data success with update etcd version: ',
                _M.etcd_version)
            local event = { plugins = { unload = {}, load = {} }, routes_l4 = { unload = {}, load = {} },
                routes_sni = { unload = {}, load = {} }, routes_l7 = { unload = {}, load = {} },
                configs = { unload = {}, load = {} } }
            for _, v in ipairs(events_data) do
                local kv = v.kv
                if kv then
                    local key = kv.key
                    if not (filter_event(key, kv, _M.plugin_prefix, event.plugins) or
                        filter_event(key, kv, _M.router_prefix_l4, event.routes_l4) or
                        filter_event(key, kv, _M.router_prefix_sni, event.routes_sni) or
                        filter_event(key, kv, _M.router_prefix_l7, event.routes_l7)) then
                        filter_event(key, kv, _M.custom_configs_prefix, event.configs)
                    end
                end
            end
            publish_event(event.plugins, 'plugins')
            publish_event(event.router_prefix_l4, 'router_l4')
            publish_event(event.router_prefix_sni, 'router_sni')
            publish_event(event.router_prefix_l7, 'router_l7')
            publish_event(event.configs, 'configs')
        end
    end

end

local function watch_etcd(premuture)
    if _M.running or premuture or exiting() then
        return
    end

    _M.running = true
    pcall(do_watch_etcd)
    _M.running = false
end

function _M.init_worker()
    timers.register_timer('watch_etcd', watch_etcd, true)
    events.register('configs', function(configs)
        for key, value in pairs(configs.unload) do
            cache[key] = nil
        end
        for key, value in pairs(configs.load) do
            cache[key] = value
        end
    end)
end

return _M
