local _M = {}

function _M.init(params)
    _M.loader = require("man.config." .. params.conf_type)
    return _M.loader.init(params)
end

function _M.init_worker()
    _M.loader.init_worker()
end

return _M
