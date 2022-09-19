local prometheus = require('man.plugins.prometheus')

local _M = { name = "prometheus-exporter" }

function _M.rewrite(ctx)
    ctx._no_prometheus_log = true
    prometheus.export(ctx)
end

return _M
