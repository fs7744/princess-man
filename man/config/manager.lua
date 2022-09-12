local _M = {}

local loader
function _M.init(params)
    loader = require("man.config." .. params.conf_type)
    return loader.init(params)
end

function _M.init_worker()
    loader.init_worker()
end

function _M.get_config(key)
    return loader.get_config(key)
end

return _M
