local prometheus_lib = require("prometheus")
local log = require("man.core.log")
local request = require("man.core.request")
local response = require("man.core.response")
local manager = require("man.config.manager")
local clear_table = require("man.core.table").clear
local ngx_shared = ngx.shared
local real_log = log._ngx_log

local _M = { priority = -999, name = "prometheus" }

local prometheus
local DEFAULT_BUCKETS = {
    1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 30000, 60000
}

local metrics = {}

local inner_arr = {}

local function gen_arr(...)
    clear_table(inner_arr)
    for i = 1, select('#', ...) do
        inner_arr[i] = select(i, ...)
    end

    return inner_arr
end

local label_values = {}
local log_levels = {
    [ngx.STDERR] = 'STDERR',
    [ngx.EMERG] = 'EMERG',
    [ngx.ALERT] = 'ALERT',
    [ngx.CRIT] = 'CRIT',
    [ngx.ERR] = 'ERR',
    [ngx.WARN] = 'WARN',
    [ngx.NOTICE] = 'NOTICE',
    [ngx.INFO] = 'INFO',
    [ngx.DEBUG] = 'DEBUG'
}
local min_log_level = ngx.NOTICE
local function log_counter(level, ...)
    local info = debug.getinfo(2, "Sl")
    real_log(level, info.short_src, ":", info.currentline, " ", ...)
    if level <= min_log_level then
        metrics.log:inc(1, gen_arr(log_levels[level]))
    end
end

function _M.start()
    clear_table(metrics)
    prometheus = prometheus_lib.init("prometheus-metrics", "edge_")
    metrics.connections = prometheus:gauge("nginx_http_current_connections",
        "Number of HTTP connections",
        { "state" })

    metrics.node_info = prometheus:gauge("node_info", "Edge agent node",
        { "hostname" })

    metrics.status = prometheus:counter("http_status",
        "HTTP status codes per service", {
        "code", "matched_host"
    })

    metrics.latency = prometheus:histogram("http_latency",
        "HTTP request latency in milliseconds per service",
        {
            "type", "matched_host"
        }, DEFAULT_BUCKETS)

    metrics.bandwidth = prometheus:counter("bandwidth",
        "Total bandwidth in bytes consumed per service",
        {
            "type", "matched_host"
        })

    metrics.config_reachable = prometheus:gauge("config_reachable",
        "Config server reachable from edge, 0 is unreachable")

    metrics.shared = prometheus:gauge("nginx_shared", "Shared dict status",
        { "key", "type" })

    metrics.log = prometheus:counter("log", "log counter", { "level" })
    log._ngx_log = log_counter
    ngx.log = log_counter
end

function _M.log(ctx)
    if ctx._no_prometheus_log then
        return
    end
    ngx.update_time()
    local latency = (ngx.now() - ngx.req.start_time()) * 1000
    request.set_var(ctx, 'latency', latency)
    local vars = ctx.var
    local matched_host = vars.http_x_origin_host

    metrics.status:inc(1, gen_arr(math.floor(vars.status / 100) .. 'xx', matched_host))
    metrics.latency:observe(latency, gen_arr("request", matched_host))
    local upstream_latency = ((vars.upstream_response_time or 0) + (vars.upstream_connect_time or 0) +
        (vars.upstream_queue_time or 0)) * 1000
    metrics.latency:observe(upstream_latency, gen_arr("upstream",
        matched_host))
    latency = latency - upstream_latency
    request.set_var(ctx, 'edge_latency', latency)
    metrics.latency:observe(latency, gen_arr("edge", matched_host))

    metrics.bandwidth:inc(vars.request_length, gen_arr("ingress", matched_host))

    metrics.bandwidth:inc(vars.bytes_sent, gen_arr("egress", matched_host))
end

function _M.export(ctx)
    if not prometheus or not metrics then
        log.error("prometheus: plugin is not initialized, please make sure ",
            " 'prometheus_metrics' shared dict is present in nginx template")
        response.exit(500, "An unexpected error occurred")
        return
    end

    label_values[1] = 'active'
    metrics.connections:set(ngx.var.connections_active, label_values)
    label_values[1] = 'reading'
    metrics.connections:set(ngx.var.connections_reading, label_values)
    label_values[1] = 'writing'
    metrics.connections:set(ngx.var.connections_writing, label_values)
    label_values[1] = 'waiting'
    metrics.connections:set(ngx.var.connections_waiting, label_values)

    local vars = ngx.var or {}
    local hostname = vars.hostname or ""

    metrics.node_info:set(1, gen_arr(hostname))

    if manager.loader.etcd_version > 0 then
        local ok, err = manager.config_reachable()
        if ok then
            metrics.config_reachable:set(1)

        else
            metrics.config_reachable:set(0)
            log.error(
                "prometheus: failed to reach config server while processing metrics endpoint: ",
                err)
        end
    end

    for key, value in pairs(ngx_shared) do
        metrics.shared:set(value:capacity(), gen_arr(key, 'capacity'))
        metrics.shared:set(value:free_space(), gen_arr(key, 'free_space'))
    end

    response.set_header("content_type", "text/plain")
    ctx._stop = true
    ngx.status = 200
    ngx.print(prometheus:metric_data())
    ngx.exit(200)
end

return _M
