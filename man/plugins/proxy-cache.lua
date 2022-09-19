local log = require('man.core.log')
local response = require('man.core.response')
local request = require('man.core.request')
local table = require('man.core.table')
local str = require('man.core.string')
local file = require('man.core.file')
local context = require("man.core.context")
local lrucache = require "resty.lrucache"
local no_cache_status = lrucache.new(1000)

local _M = { priority = 18500, name = "proxy-cache" }

local tmp = {}
local function generate_complex_value(data, ctx)
    table.clear(tmp)

    for i, value in ipairs(data) do
        log.info("proxy-cache complex value index-", i, ": ", value)

        if string.byte(value, 1, 1) == string.byte('$') then
            tmp[i] = ctx.var[string.sub(value, 2)]
        else
            tmp[i] = value
        end
    end

    return ctx.matched_router.id .. table.concat(tmp, "")
end

local function match_method(conf, ctx)

    local matchd_method = false

    for _, method in ipairs(conf.method) do
        if method == ctx.var.request_method then
            matchd_method = true
            break
        end
    end

    return matchd_method
end

local function match_status(conf)

    local matchd_status = false

    for _, status in ipairs(conf.status) do
        if status == ngx.status then
            matchd_status = true
            break
        end
    end

    return matchd_status
end

local function generate_cache_file_name(cache_path, cache_levels, cache_key)
    local md5sum = ngx.md5(cache_key)
    local levels = str.split(cache_levels, ":")
    local filename = ""

    local index = #md5sum
    for _, v in pairs(levels) do
        local length = tonumber(v)
        index = index - length
        filename = filename .. md5sum:sub(index + 1, index + length) .. "/"
    end
    if cache_path:sub(-1) ~= "/" then
        cache_path = cache_path .. "/"
    end
    filename = cache_path .. filename .. md5sum
    return filename
end

local function cache_purge(ctx)
    local cache_zone_info = str.split(ctx.var.upstream_cache_zone_info, ",")

    local filename = generate_cache_file_name(cache_zone_info[1],
        cache_zone_info[2],
        ctx.var.upstream_cache_key)
    if file.exists(filename) then
        os.remove(filename)
        response.exit(200)
        return
    end

    response.exit(404)
end

local function checkPathIfNotFileRequest(ctx, conf)
    if conf.check_http_cache_control then
        local http_cache_control = ctx.var.http_cache_control
        if http_cache_control and str.has_prefix(http_cache_control, 'no-') then
            return true
        end
    end
    if conf.not_allow_list then
        if context.is_req_in_allow_list(ctx, conf.not_allow_list) then
            return true
        end
    end
    if conf.only_allow_file_ext == true then
        local ext = str.get_file_ext(ctx.var.uri)
        if not ext or (conf.not_allow_file_ext and conf.not_allow_file_ext[ext] == true) then
            return true
        end
        return false
    end

    return false
end

function _M.rewrite(ctx)
    local conf = ctx.matched_router.cache
    if not conf or not match_method(conf, ctx) or checkPathIfNotFileRequest(ctx, conf) then
        return
    end
    if conf.no_cache ~= nil then
        local value = generate_complex_value(conf.no_cache, ctx)
        if value ~= nil and value ~= "" and value ~= "0" then
            return
        end
    end
    local value = generate_complex_value(conf.key, ctx)
    local status, err = no_cache_status:get(value)
    if status then
        return
    end
    ctx._upstream_cache = true
    request.set_var(ctx, 'upstream_cache_zone', conf.zone)
    request.set_var(ctx, 'upstream_cache_key', value)
    log.info("proxy-cache key:", value)

    if ctx.var.request_method == "PURGE" then
        cache_purge(ctx)
        return
    end

    if conf.bypass ~= nil then
        value = generate_complex_value(conf.bypass, ctx)
        request.set_var(ctx, 'upstream_cache_bypass', value)
        log.info("proxy-cache bypass:", value)
    end
end

function _M.header_filter(ctx)
    local conf = ctx.matched_router.cache
    if not conf or ctx._upstream_cache ~= true then
        return
    end

    if match_status(conf) then
        no_cache_status:delete(ctx.var.upstream_cache_key)
        response.set_header("Cache-Control", ctx.var.upstream_http_cache_control,
            "Expires", ctx.var.upstream_http_expires,
            "Edge-Cache-Status", ctx.var.upstream_cache_status)
    else
        request.set_var(ctx, 'upstream_no_cache', '0')
        log.info("proxy-cache no cache:", '0')
        no_cache_status:set(ctx.var.upstream_cache_key, true, 60)
    end
end

return _M
