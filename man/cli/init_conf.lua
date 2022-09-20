--local template = require("resty.template")
local file = require("man.core.file")
local yaml = require("man.config.yaml")
local etcd = require("man.config.etcd")
local str = require("man.core.string")
local json = require("man.core.json")
local cmd = require("man.cli.cmd")

local tpl = [=[
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

    {% if dns then %}
    {% if dns.timeout_str then %}
    resolver_timeout {* dns.timeout_str *};
    {% end %}
    resolver {% for _, dns_addr in ipairs(dns.nameservers or {}) do %} {*dns_addr*} {% end %} {% if dns.validTtl_str then %} valid={*dns.validTtl_str*}{% end %} ipv6={% if dns.enable_ipv6 then %}on{% else %}off{% end %};
    {% end %}

    {% if stream.access_log then %}
    {% if stream.access_log.enable == false then %}
    access_log off;
    {% else %}
    {% if not stream.access_log.file then stream.access_log.file = 'logs/access.log' end %}
    log_format main '{* stream.access_log.format *}';
    access_log {* stream.access_log.file *} main buffer=16384 flush=3;
    {% end %}
    {% end %}

    {% if not stream.lua_shared_dict then stream.lua_shared_dict = {} end %}
    {% if not stream.lua_shared_dict['lrucache_lock'] then stream.lua_shared_dict['lrucache_lock'] = '10m' end %}
    {% for key, size in pairs(stream.lua_shared_dict) do %}
    lua_shared_dict {*key*} {*size*};
    {% end %}

    {% if stream.config then %}
    {% for key, v in ipairs(stream.config) do %}
    {*v*};
    {% end %}
    {% end %}

    upstream man_upstream {
        server 0.0.0.1:80;

        balancer_by_lua_block {
            Man.balancer()
        }
    }

    init_by_lua_block {
        Man = require 'man'
        Man.init([[{* init_params *}]])
    }

    init_worker_by_lua_block {
        Man.init_worker()
    }

    server {
        {% if router and router.l4 then %}
        {% for k, i in pairs(router.l4) do %}
        {% if i and i.listen then %}
        listen {* i.listen *} {% if i.ssl then %} ssl {% end %} {% if i.type == 'udp' then %} udp {% end %} {% if enable_reuseport then %} reuseport {% end %};
        {% end %}    
        {% end %}
        {% end %}
        
        {% if stream.server_config then %}
        {% for key, v in ipairs(stream.server_config) do %}
        {*v*};
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
        {% if not stream.ssl.protocols then stream.ssl.protocols = 'TLSv1 TLSv1.1 TLSv1.2 TLSv1.3' end %}
        ssl_protocols {* stream.ssl.protocols *};
   
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
            Man.log()
        }
    }
}
{% end %}

http {
    lua_package_path  "{*lua_package_path*}$prefix/deps/share/lua/5.1/?.lua;$prefix/deps/share/lua/5.1/?/init.lua;$prefix/?.lua;$prefix/?/init.lua;;./?.lua;/usr/local/openresty/luajit/share/luajit-2.1.0-beta3/?.lua;/usr/local/share/lua/5.1/?.lua;/usr/local/share/lua/5.1/?/init.lua;/usr/local/openresty/luajit/share/lua/5.1/?.lua;/usr/local/openresty/luajit/share/lua/5.1/?/init.lua;";
    lua_package_cpath "{*lua_package_cpath*}$prefix/deps/lib64/lua/5.1/?.so;$prefix/deps/lib/lua/5.1/?.so;;./?.so;/usr/local/lib/lua/5.1/?.so;/usr/local/openresty/luajit/lib/lua/5.1/?.so;/usr/local/lib/lua/5.1/loadall.so;";
    lua_socket_log_errors off;
    lua_code_cache on;

    {% if http then %}
    {% if not http.lua_shared_dict then http.lua_shared_dict = {} end %}
    {% if not http.lua_shared_dict['http_lrucache_lock'] then http.lua_shared_dict['http_lrucache_lock'] = '10m' end %}
    {% for key, size in pairs(http.lua_shared_dict) do %}
    lua_shared_dict {*key*} {*size*};
    {% end %}
    {% end %}

    {% if http.config then %}
    {% for key, v in ipairs(http.config) do %}
    {*v*};
    {% end %}
    {% end %}

    init_by_lua_block {
        Man = require 'man'
        Man.init([[{* init_params *}]])
    }

    {% if http and http.enable == true then %}
    upstream man_upstream {
        server 0.0.0.1:80;

        balancer_by_lua_block {
            Man.balancer()
        }
    }

    init_worker_by_lua_block {
        Man.init_worker()
    }

    server {
        {% if not http.ssl then http.ssl = { enable = false} end %}
        {% if http.ssl.enable then %}
        ssl_certificate      {* http.ssl.cert *};
        ssl_certificate_key  {* http.ssl.cert_key *};
        {% if not http.ssl.session_cache then http.ssl.session_cache = 'shared:HTTP_SSL:20m' end %}
        ssl_session_cache   {* http.ssl.session_cache *};
        {% if not http.ssl.session_timeout then http.ssl.session_timeout = '10m' end %}
        ssl_session_timeout {* http.ssl.session_timeout *};
        {% if not http.ssl.protocols then http.ssl.protocols = 'TLSv1 TLSv1.1 TLSv1.2 TLSv1.3' end %}
        ssl_protocols {* http.ssl.protocols *};
        proxy_ssl_protocols {* http.ssl.protocols *};
        proxy_ssl_server_name on;
        {% if not http.ssl.ciphers then http.ssl.ciphers = 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384' end %}
        ssl_ciphers {* http.ssl.ciphers *};
        ssl_prefer_server_ciphers on;
        {% if http.ssl.session_tickets then %}
        ssl_session_tickets on;
        {% else %}
        ssl_session_tickets off;
        {% end %}
        {% end %}

        {% if http.server_config then %}
        {% for key, v in ipairs(http.server_config) do %}
        {*v*};
        {% end %}
        {% end %}

        {% if http.access_log then %}
        {% if http.access_log.enable == false then %}
        access_log off;
        {% else %}
        {% if not http.access_log.file then http.access_log.file = 'logs/access.log' end %}
        log_format main '{* http.access_log.format *}';
        access_log {* http.access_log.file *} main buffer=16384 flush=3;
        {% end %}
        {% end %}

        location / {
            set $upstream_mirror_host        '';
            set $upstream_scheme             '';
            set $upstream_uri                '';
            set $upstream_upgrade                '';
            set $upstream_connection                '';
            set $reason     '';

            access_by_lua_block {
                Man.access()
            }

            proxy_ssl_protocols {* http.ssl.protocols *};
            proxy_ssl_server_name on;
            proxy_http_version                  1.1;

            proxy_set_header Upgrade $upstream_upgrade;
            proxy_set_header Connection $upstream_connection;
            proxy_set_header  Host    $proxy_host;
            proxy_pass      $upstream_scheme://man_upstream$upstream_uri;
            mirror          /proxy_mirror;

            header_filter_by_lua_block {
                Man.header_filter()
            }

            body_filter_by_lua_block {
                Man.body_filter()
            }

            log_by_lua_block {
                Man.log()
            }
        }

        location = /proxy_mirror {
            internal;
            if ($upstream_mirror_host = "") {
                return 200;
            }

            proxy_pass $upstream_scheme://$upstream_mirror_host$upstream_uri;
        }

        location @grpc_pass {

            access_by_lua_block {
                Man.grpc_access()
            }

            grpc_set_header   Content-Type application/grpc;
            grpc_socket_keepalive on;
            grpc_pass         $upstream_scheme://man_upstream;

            header_filter_by_lua_block {
                Man.header_filter()
            }

            body_filter_by_lua_block {
                Man.body_filter()
            }

            log_by_lua_block {
                Man.log()
            }
        }
    }

    {% end %}
    # create a listening unix domain socket
    server {
        listen unix:/tmp/events.sock;
        location / {
            content_by_lua_block {
                require('man.core.events').run()
            }
        }
    }
    
}

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

local function check_conf(conf, args)
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

    if not conf.process_events then
        conf.process_events = '10m'
    end
    if conf.dns then
        if conf.dns.timeout then
            conf.dns.timeout_str = (conf.dns.timeout / 1000) .. 's'
        end
        if conf.dns.validTtl then
            conf.dns.validTtl_str = (conf.dns.validTtl / 1000) .. 's'
        end
    end
    if conf.router and conf.router.l4 and args.local_ips then
        package.loaded['man.config.manager'] = {
            get_config = function(key)
                return args
            end
        }
        local l4 = require('man.router.l4')
        for _, value in pairs(conf.router.l4) do
            if not l4.filter(value) then
                value.listen = nil
            end
        end
    end
    return conf
end

function _M.generate(env, args)
    local content, err, conf
    if type(args.local_ips) == 'string' then
        args.local_ips = { args.local_ips }
    end
    if str.has_prefix(str.lower(args.require), 'http') then
        if not args.etcd_prefix or str.trim(args.etcd_prefix) == '' then
            return nil, 'etcd_prefix is required.'
        end
        local p = {
            conf_type = 'etcd',
            conf_file = args.conf,
            etcd_conf = {
                key_prefix = args.etcd_prefix,
                timeout = args.etcd_timeout,
                http_host = args.require,
                user = args.user,
                password = args.password,
                ssl_verify = args.ssl_verify,
                ttl = args.ttl,
            },
            home = env.home,
            local_ips = args.local_ips
        }
        etcd.init(p)
        conf = etcd.get_config('man')
        if not conf then
            return nil, 'not found config man in etcd'
        end
        conf.init_params = json.encode(p)
    else
        conf, err = yaml.read_conf(args.require)
        if err then
            return nil, err
        end
        conf.init_params = json.encode({
            conf_type = 'yaml',
            conf_file = args.conf,
            yaml_file = args.require,
            home = env.home,
            local_ips = args.local_ips,
            dns = conf.dns
        })
    end

    content = check_conf(conf, args)
    content, err = file.overwrite(args.conf, require("resty.template").compile(tpl)(content))
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
