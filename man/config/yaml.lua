local log = require('man.core.log')

local _M = {}

function _M.init(params)
    log.error(require('man.core.json').encode(params))
end

return _M
