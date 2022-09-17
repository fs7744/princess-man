local require = require
local json = require "man.core.json"
local pkg_loaded = package.loaded
local table = require("man.core.table")
local log = require("man.core.log")
local config = require("man.config.manager")
local is_http = require('man.core.ngp').is_http_system()

local plugin_method = {
    "rewrite", "access", "header_filter", "body_filter", "log"
}

local _M = { load_times = 0, plugins_hash = {}, handlers = {} }

local function load_plugin(p, plugins_list, plugins_hash)
    local pkg_name = p.plugin
    local ok, plugin = pcall(require, pkg_name)
    log.info('load plugin [', pkg_name, ']')
    if not ok then
        log.error('load plugin [', pkg_name, '] err:', plugin)
        return
    end
    plugin.plugin = pkg_name
    plugins_hash[pkg_name] = plugin
    table.insert(plugins_list, plugin)
    if plugin.init then
        plugin.init(p)
    end
    return plugin
end

local function unload_plugin(p)
    log.info('load plugin [', p, ']')
    local old_plugin = pkg_loaded[p]
    if old_plugin and type(old_plugin.destroy) == "function" then
        old_plugin.destroy()
    end

    pkg_loaded[p] = nil
end

local function sort_plugin(l, r)
    return l.priority > r.priority
end

local function create_handler(func, func_name)
    return function(ctx)
        local r, err = pcall(func, ctx)
        if not r then
            log.error(func_name, ' exec failed: ', err)
            ctx._stop = true
        end
    end
end

local function create_handlers(plugins)
    local handlers = table.new(0, #plugin_method)
    for _, m_name in pairs(plugin_method) do
        local handler = {}
        handlers[m_name] = handler
        for _, plugin in pairs(plugins) do
            local m = plugin[m_name]
            if m then
                table.insert(handler,
                    create_handler(m, m_name .. '_' .. plugin.plugin))
            end
        end
    end
    return handlers
end

function _M.load(plugin_list)
    local unload = plugin_list.unload
    local load = plugin_list.load
    local new_plugins_list = {}
    local new_plugins_hash = {}
    local old_plugins = _M.plugins_hash
    for k, _ in pairs(unload) do
        unload_plugin(k)
    end

    for _, p in pairs(load) do
        load_plugin(p, new_plugins_list, new_plugins_hash)
    end

    for k, p in pairs(old_plugins) do
        if not unload[k] and not load[k] then
            new_plugins_hash[k] = p
            table.insert(new_plugins_list, p)
        end
    end

    if #new_plugins_list > 1 then
        table.sort(new_plugins_list, sort_plugin)
    end

    local handlers = create_handlers(new_plugins_list)
    local version = _M.load_times + 1
    _M.handlers = handlers
    _M.plugins_hash = new_plugins_hash
    _M.load_times = version
end

function _M.run(fnName, api_ctx)
    if api_ctx then
        if api_ctx._stop then
            return api_ctx._stop
        end
        local hs = _M.handlers[fnName]
        if hs then
            for i = 1, #hs do
                hs[i](api_ctx)
                if api_ctx._stop then
                    return api_ctx._stop
                end
            end
        end
    end
    return false
end

function _M.run_no_stop(fnName, api_ctx)
    if api_ctx then
        local hs = _M.handlers[fnName]
        if hs then
            for i = 1, #hs do
                hs[i](api_ctx)
            end
        end
    end
    return false
end

function _M.init_worker()
    local plugins = config.get_config('plugins')
    if plugins then
        local ps
        if is_http then
            ps = plugins.http
        else
            ps = plugins.stream
        end
        if ps then
            _M.load({ unload = {}, load = ps })
        end
    end
end

return _M
