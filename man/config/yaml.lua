local log    = require('man.core.log')
local timers = require("man.core.timers")
local file   = require("man.core.file")
local ngp    = require("man.core.ngp")
local yaml   = require("tinyyaml")
local lfs    = require("lfs")

local _M = {}

local cahche = {}
local yaml_change_time
function _M.init(params)
    _M.params = params
    local attributes, err = lfs.attributes(_M.params.yaml_file)
    yaml_change_time = attributes.change
end

local function watch_yaml()
    local attributes, err = lfs.attributes(_M.params.yaml_file)
    if not attributes then
        log.error("failed to fetch ", _M.params.yaml_file, " attributes: ", err)
        return
    end
    local last_change_time = attributes.change
    if yaml_change_time == last_change_time then
        return
    end
    yaml_change_time = last_change_time
    os.execute('sh ' .. _M.params.home .. '/princess.sh init -r ' .. _M.params.yaml_file .. ' -c ' .. _M.params.conf_file)
    attributes, err = ngp.reload()
    if err then
        log.error(err)
    end
end

function _M.init_worker()
    timers.register_timer('watch_yaml', watch_yaml, true)

    local conf, err = _M.read_conf(_M.params.yaml_file)
    if err then
        return nil, err
    end
    cahche.man = conf
    cahche.router = conf.router
    cahche.params = _M.params
    cahche.plugins = conf.plugins
    conf.router = nil
    conf.plugins = nil
end

function _M.read_conf(conf_path)
    if not file.exists(conf_path) then
        return nil, 'not exists yaml: ' .. conf_path
    end
    local content, err = file.read_all(conf_path)
    if err then
        return nil, err
    end

    local conf = yaml.parse(content)
    if not conf then
        return nil, "invalid yaml: " .. conf_path
    end
    return conf, nil
end

function _M.get_config(key)
    return cahche[key]
end

return _M
