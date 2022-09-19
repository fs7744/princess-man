local lru_new = require("resty.lrucache").new
local resty_lock = require("resty.lock")
local log = require("man.core.log")
local ngx = ngx
local get_phase = ngx.get_phase

local lock_shdict_name = "lrucache_lock"

if require('man.core.ngp').is_http_system() then
    lock_shdict_name = "http_lrucache_lock"
end

local can_yield_phases = {
    ssl_session_fetch = true,
    ssl_session_store = true,
    rewrite = true,
    access = true,
    content = true,
    timer = true
}

local GLOBAL_ITEMS_COUNT = 1024
local GLOBAL_TTL = 60 * 60 -- 60 min
local global_lru_fun

local function fetch_valid_cache(lru_obj, invalid_stale, item_ttl, item_release,
                                 key, version)
    local obj, stale_obj = lru_obj:get(key)
    if obj and obj.ver == version then
        return obj
    end

    if not invalid_stale and stale_obj and stale_obj.ver == version then
        lru_obj:set(key, stale_obj, item_ttl)
        return stale_obj
    end

    if item_release and obj then
        item_release(obj.val)
    end

    return nil
end

local function new_lru_fun(opts)
    local item_count = GLOBAL_ITEMS_COUNT
    local item_ttl = GLOBAL_TTL
    local item_release, invalid_stale, serial_creating
    if opts then
        item_count = opts.item_count or GLOBAL_ITEMS_COUNT
        item_ttl = opts.item_ttl or GLOBAL_TTL
        item_release = opts.release
        invalid_stale = opts.invalid_stale
        serial_creating = opts.serial_creating
    end

    local lru_obj = lru_new(item_count)

    return function(key, version, create_obj_fun, ...)
        if not serial_creating or not can_yield_phases[get_phase()] then
            local cache_obj = fetch_valid_cache(lru_obj, invalid_stale,
                item_ttl, item_release, key,
                version)
            if cache_obj then
                return cache_obj.val
            end

            local obj, err = create_obj_fun(...)
            if obj ~= nil then
                lru_obj:set(key, { val = obj, ver = version }, item_ttl)
            end

            return obj, err
        end

        local cache_obj = fetch_valid_cache(lru_obj, invalid_stale, item_ttl,
            item_release, key, version)
        if cache_obj then
            return cache_obj.val
        end

        local lock, err = resty_lock:new(lock_shdict_name)
        if not lock then
            return nil, "failed to create lock: " .. err
        end

        local key_s = tostring(key)

        local elapsed
        elapsed, err = lock:lock(key_s)
        if not elapsed then
            return nil, "failed to acquire the lock: " .. err
        end

        cache_obj = fetch_valid_cache(lru_obj, invalid_stale, item_ttl, nil,
            key, version)
        if cache_obj then
            lock:unlock()
            return cache_obj.val
        end

        local obj
        obj, err = create_obj_fun(...)
        if obj ~= nil then
            lru_obj:set(key, { val = obj, ver = version }, item_ttl)
        end
        lock:unlock()

        return obj, err
    end
end

global_lru_fun = new_lru_fun()

local _M = { version = 0.1, new = new_lru_fun, global = global_lru_fun }

return _M
