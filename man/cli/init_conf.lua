local template = require("resty.template")
local file = require("man.core.file")
local json = require("man.core.json")
local yaml = require("tinyyaml")
local str = require("man.core.string")
local cmd = require("man.cli.cmd")

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
    lua_socket_log_errors off;
    lua_code_cache on;

    {% if tcp_nodelay == false then %}
    tcp_nodelay off;
    {% else %}
    tcp_nodelay on;
    {% end %}

    {% if max_pending_timers then %}
    lua_max_pending_timers {* max_pending_timers *};
    {% end %}
    {% if max_running_timers then %}
    lua_max_running_timers {* max_running_timers *};
    {% end %}
    {% if preread_buffer_size then %}
    preread_buffer_size {* preread_buffer_size *};
    {% end %}
    {% if preread_timeout then %}
    preread_timeout {* preread_timeout *};
    {% end %}
    {% if proxy_buffer_size then %}
    proxy_buffer_size {* proxy_buffer_size *};
    {% end %}
    {% if proxy_connect_timeout then %}
    proxy_connect_timeout {* proxy_connect_timeout *};
    {% end %}
    {% if proxy_download_rate then %}
    proxy_download_rate {* proxy_download_rate *};
    {% end %}
    {% if proxy_half_close then %}
    proxy_half_close {* proxy_half_close *};
    {% end %}
    {% if proxy_requests then %}
    proxy_requests {* proxy_requests *};
    {% end %}
    {% if proxy_responses then %}
    proxy_responses {* proxy_responses *};
    {% end %}
    {% if proxy_session_drop then %}
    proxy_session_drop {* proxy_session_drop *};
    {% end %}
    {% if proxy_timeout then %}
    proxy_timeout {* proxy_timeout *};
    {% end %}
    {% if proxy_upload_rate then %}
    proxy_upload_rate {* proxy_upload_rate *};
    {% end %}
    {% if proxy_socket_keepalive then %}
    proxy_socket_keepalive {* proxy_socket_keepalive *};
    {% end %}
    {% if proxy_protocol_timeout then %}
    proxy_protocol_timeout {* proxy_protocol_timeout *};
    {% end %}
    {% if variables_hash_bucket_size then %}
    variables_hash_bucket_size {* variables_hash_bucket_size *};
    {% end %}
    {% if variables_hash_max_size then %}
    variables_hash_max_size {* variables_hash_max_size *};
    {% end %}
    {% if proxy_bind then %}
    proxy_bind {* proxy_bind *};
    {% end %}
    {% if resolver_timeout then %}
    resolver_timeout {* resolver_timeout *};
    {% end %}
    resolver {% for _, dns_addr in ipairs(dns_resolver or {}) do %} {*dns_addr*} {% end %} {% if dns_resolver_valid then %} valid={*dns_resolver_valid*}{% end %} ipv6={% if enable_ipv6 then %}on{% else %}off{% end %};

    {% if stream.access_log then %}
    {% if stream.access_log.enable == false then %}
    access_log off;
    {% else %}
    log_format main '{* stream.access_log.format *}';
    access_log {* stream.access_log.file *} main buffer=16384 flush=3;
    {% end %}
    {% end %}

    {% if stream.lua_shared_dict then %}
    {% for key, size in pairs(stream.lua_shared_dict) do %}
    lua_shared_dict {*key*} {*size*};
    {% end %}
    {% end %}

    upstream man_upstream {
        server 0.0.0.1:80;

        balancer_by_lua_block {
            Man.stream_balancer()
        }
    }

    init_by_lua_block {
        Man = require 'man'
        Man.init({* init_params *})
    }

    init_worker_by_lua_block {
        Man.stream_init_worker()
    }

    server {
        {% if router then %}
        {% for k, i in pairs(router) do %}
        {% if i.l4 and i.l4.listen then %}
        listen {* i.l4.listen *} {% if i.l4.ssl then %} ssl {% end %} {% if i.l4.type == 'udp' then %} udp {% end %} {% if enable_reuseport then %} reuseport {% end %};
        {% end %}    
        {% end %}
        {% end %}
        {% if not stream.ssl then stream.ssl = { enable = false} end %}
        {% if stream.ssl.enable then %}
        ssl_certificate      {* stream.ssl.cert *};
        ssl_certificate_key  {* stream.ssl.cert_key *};
        {% if not stream.ssl.session_cache then stream.ssl.session_cache = 'shared:SSL:20m' end %}
        ssl_session_cache   {* stream.ssl.session_cache *};
        {% if not stream.ssl.session_timeout then stream.ssl.session_timeout = '10m' end %}
        ssl_session_timeout {* stream.ssl.session_timeout *};
        {% if not stream.ssl.protocols then stream.ssl.protocols = 'TLSv1 TLSv1.1 TLSv1.2' end %}
        ssl_protocols {* stream.ssl.protocols *};
        {% if not stream.ssl.ciphers then stream.ssl.ciphers = 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384' end %}
        ssl_ciphers {* stream.ssl.ciphers *};
        ssl_prefer_server_ciphers on;
        {% if stream.ssl.session_tickets then %}
        ssl_session_tickets on;
        {% else %}
        ssl_session_tickets off;
        {% end %}

        ssl_certificate_by_lua_block {
            Man.stream_ssl_certificate()
        }
        {% end %}

        preread_by_lua_block {
            Man.stream_preread()
        }

        proxy_pass man_upstream;

        log_by_lua_block {
            Man.stream_log()
        }
    }
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
    local content, err, conf
    if str.has_prefix(str.lower(args.require), 'http') then
        if not args.etcd_prefix or str.trim(args.etcd_prefix) == '' then
            return nil, 'etcd_prefix is required.'
        end

        conf = { init_params = "{conf_type = 'etcd', etcd_prefix = '" ..
            args.etcd_prefix ..
            "', etcd_timeout = " ..
            args.etcd_timeout ..
            ", etcd_host = '" .. args.require .. "', conf_file = '" .. args.conf .. "', home = '" .. env.home .. "'}" }
    else
        if file.exists(args.require) then
            content, err = file.read_all(args.require)
        end
        if err then
            return nil, err
        end
        if not content or content == '' then
            content = 'man:'
        end
        conf = yaml.parse(content)
        if not conf then
            return nil, 'Invalid conf yaml'
        end
        conf = conf.man
        conf.init_params = "{conf_type = 'yaml', conf_file = '" ..
            args.conf .. "', yaml_file = '" .. args.require .. "', home = '" .. env.home .. "'}"
    end

    content = check_conf(conf)
    content, err = file.overwrite(args.conf, template.compile(tpl)(content))
    if err then
        return nil, err
    end
    if cmd.execute_cmd(env.openresty_args .. args.conf .. ' -t') then
        return 'Generated success at: ' .. args.conf
    else
        return 'Generated failed'
    end
end

return _M
