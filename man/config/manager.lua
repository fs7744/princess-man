local _M = {}

function _M.init(params)
    _M.loader = require("man.config." .. params.conf_type)
    return _M.loader.init(params)
end

return _M
