local log = require('man.core.log')

local _M = { priority = 0, name = "serverless" }

local function call_func(methodName, ctx)
    if not ctx.matched_router then
        return
    end
    local conf = ctx.matched_router.serverless
    if not conf then
        return
    end

    local funcs = conf.funcs
    local success, err
    if not funcs then
        if conf.file then
            success, funcs = pcall(require, conf.file)
        else
            success, funcs = pcall(loadstring(conf.func_str))
        end

        if not success then
            log.error('require func file: ', conf.file, ' at phase: ',
                methodName, ' ,err: ', funcs)
            return
        end
        conf.funcs = funcs
        if funcs.init then
            funcs.init()
        end
    end

    local f = funcs[methodName]
    if f then
        success, err = pcall(f, ctx)
        if not success then
            log.error('call func: ', methodName, ' ,err: ', err)
        end
    end
end

function _M.rewrite(ctx)
    call_func('rewrite', ctx)
end

function _M.access(ctx)
    call_func('access', ctx)
end

function _M.header_filter(ctx)
    call_func('header_filter', ctx)
end

function _M.body_filter(ctx)
    call_func('body_filter', ctx)
end

function _M.log(ctx)
    call_func('log', ctx)
end

function _M.preread(ctx)
    call_func('preread', ctx)
end

function _M.ssl_certificate(ctx)
    call_func('ssl_certificate', ctx)
end

return _M
