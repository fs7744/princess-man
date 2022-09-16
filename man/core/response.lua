local ngx = ngx


local _M = {}

if require('man.core.ngp').is_http_system() then
    local header = ngx.header
    local ngx_add_header = require("ngx.resp").add_header
    local manager = require('man.config.manager')
    local template = require('resty.template')

    local function set_header(append, ...)
        if ngx.headers_sent then
            error("headers have already been sent", 2)
        end

        local count = select('#', ...)
        if count == 1 then
            local headers = select(1, ...)
            if type(headers) ~= "table" then
                error("should be a table if only one argument", 2)
            end

            for k, v in pairs(headers) do
                if append then
                    ngx_add_header(k, v)
                else
                    header[k] = v
                end
            end

            return
        end

        for i = 1, count, 2 do
            if append then
                ngx_add_header(select(i, ...), select(i + 1, ...))
            else
                header[select(i, ...)] = select(i + 1, ...)
            end
        end
    end

    function _M.set_header(...)
        set_header(false, ...)
    end

    function _M.add_header(...)
        set_header(true, ...)
    end

    local function handle_exit_content(code, ctx)
        local r = nil
        local content_type = nil
        local c = tostring(code)

        return r
    end

    function _M.exit(code, content)
        local ctx = ngx.ctx.api_ctx
        ctx._stop = true
        if code ~= nil then
            ngx.status = code
        end
        if not content then
            content = handle_exit_content(code, ctx)
        end
        if content then
            _M.print(content)
        end
        if code then
            ngx.exit(code)
        end
    end

    function _M.redirect(url, status, content)
        _M.set_header('Location', url)
        local code = status or 301
        _M.exit(code, content or code)
    end

    function _M.clear_header_as_body_modified()
        ngx.header.content_length = nil
        -- in case of upstream content is compressed content
        ngx.header.content_encoding = nil

        -- clear cache identifier
        ngx.header.last_modified = nil
        ngx.header.etag = nil
    end
else

    function _M.exit(code, content)
        local ctx = ngx.ctx.api_ctx
        ctx._stop = true
        if code ~= nil then
            ngx.status = code
        end
        if content then
            _M.print(content)
        end
        if code then
            ngx.exit(code)
        end
    end

end

function _M.print(content)
    if content then
        ngx.print(content)
    end
end

return _M
