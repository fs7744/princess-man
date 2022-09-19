local edgep = require('man.core.edgep')
local response = require('man.core.response')

local _M = { name = "reload-ngx" }

function _M.rewrite(ctx)
    local ok, err = edgep.reload()
    if ok then
        err = 'called reload'
    end
    response.exit(200, err)
end

return _M
