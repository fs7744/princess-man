local template = require("resty.template")
local file = require("man.core.file")
local json = require("man.core.json")
local yaml = require("tinyyaml")
local str = require("man.core.string")

local tpl = [=[
env ETCD_HOST;
env ETCD_PREFIX;
env ETCD_TIMEOUT;
{% if envs then %}
{% for _, name in ipairs(envs) do %}
env {*name*};
{% end %}
{% end %}
pid       logs/nginx.pid;
{% 
if error_log and error_log == '' then 
    error_log = 'logs/error.log'
end     
%}
error_log {* error_log *} {* error_log_level *};
{% if user and user ~= '' then %}
user {* user *};
{% end %}

worker_processes {* worker_processes *};
{% if worker_cpu_affinity and worker_cpu_affinity ~= '' then %}
worker_cpu_affinity {* worker_cpu_affinity *};
{% end %}
{% if worker_rlimit_nofile and worker_rlimit_nofile ~= '' then %}
worker_rlimit_nofile {* worker_rlimit_nofile *};
{% end %}
{% if worker_rlimit_core and worker_rlimit_core ~= '' then %}
worker_rlimit_core {* worker_rlimit_core *};
{% end %}
{% if worker_shutdown_timeout and worker_shutdown_timeout ~= '' then %}
worker_shutdown_timeout {* worker_shutdown_timeout *};
{% end %}

events {
    accept_mutex off;
    worker_connections  {* worker_connections *};
}

{% if stream and stream.enable then %}
stream {
    lua_package_path  "{*lua_package_path*}$prefix/deps/share/lua/5.1/?.lua;$prefix/deps/share/lua/5.1/?/init.lua;$prefix/?.lua;$prefix/?/init.lua;;./?.lua;/usr/local/openresty/luajit/share/luajit-2.1.0-beta3/?.lua;/usr/local/share/lua/5.1/?.lua;/usr/local/share/lua/5.1/?/init.lua;/usr/local/openresty/luajit/share/lua/5.1/?.lua;/usr/local/openresty/luajit/share/lua/5.1/?/init.lua;";
    lua_package_cpath "{*lua_package_cpath*}$prefix/deps/lib64/lua/5.1/?.so;$prefix/deps/lib/lua/5.1/?.so;;./?.so;/usr/local/lib/lua/5.1/?.so;/usr/local/openresty/luajit/lib/lua/5.1/?.so;/usr/local/lib/lua/5.1/loadall.so;";
    server_tokens off;
    lua_socket_log_errors off;
    uninitialized_variable_warn off;
    {% if max_pending_timers then %}
    lua_max_pending_timers {* max_pending_timers *};
    {% end %}
    {% if max_running_timers then %}
    lua_max_running_timers {* max_running_timers *};
    {% end %}
}
{% end %}

]=]

local _M = {}

local function check_conf_string(conf, key, contains)
    local v = conf[key]
    if type(v) == "string" then
        v = str.lower(str.trim(v or ''))
        if str.contains(';' .. contains .. ';', ';' .. v .. ';') then
            conf[key] = v
            return true
        end
    end
    return false
end

local function check_conf_number(conf, key)
    local v = tonumber(conf[key])
    if v then
        conf[key] = v
        return true
    end
    return false
end

local function check_conf(conf)
    if not conf then
        conf = {}
    end
    if not check_conf_string(conf, 'worker_processes', 'auto')
        and not check_conf_number(conf, 'worker_processes') then
        conf.worker_processes = 'auto'
    end
    if not check_conf_string(conf, 'error_log_level', 'stderr;emerg;alert;crit;error;warn;notice;info;debug') then
        conf.error_log_level = 'warn'
    end
    if not check_conf_number(conf, 'worker_rlimit_nofile') then
        conf.worker_rlimit_nofile = ''
    end
    if not check_conf_number(conf, 'worker_connections') then
        conf.worker_connections = 512
    end
    return conf
end

function _M.generate(env, args)
    local content, err
    if file.exists(args.conf) then
        content, err = file.read_all(args.conf)
    end
    if err then
        return nil, err
    end
    if not content or content == '' then
        content = 'man:'
    end
    local conf = yaml.parse(content)
    if not conf then
        return nil, 'Invalid conf yaml'
    end
    -- if args.debug then
    --     print(json.encode(conf.man))
    -- end
    content = check_conf(conf.man)
    -- if args.debug then
    --     print(json.encode(content))
    -- end
    content, err = file.overwrite(args.output, template.compile(tpl)(content))
    if err then
        return nil, err
    end
    return 'Generated at: ' .. args.output
end

return _M
