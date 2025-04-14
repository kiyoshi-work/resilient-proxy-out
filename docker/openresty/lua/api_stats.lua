local _M = {}
local redis = require "resty.redis"
local cjson = require "cjson"
local utils = require "utils"

-- Constants for Redis keys
local STATS_PREFIX = "api_stats:"
local DAILY_STATS_PREFIX = "api_stats_daily:"
local HOURLY_STATS_PREFIX = "api_stats_hourly:"

-- Function to get Redis connection
local function get_redis(host, port, password, timeout)
    local red = redis:new()
    red:set_timeout(timeout)
    local ok, err = red:connect(host, port)
    if not ok then
        utils.log(ngx.ERR, "Failed to connect to Redis: " .. (err or "unknown error"))
        return nil, err
    end
    
    -- Authenticate if password is provided
    if password then
        local auth_ok, auth_err = red:auth(password)
        if not auth_ok then
            utils.log(ngx.ERR, "Failed to authenticate with Redis: " .. (auth_err or "unknown error"))
            return nil, auth_err
        end
    end
    return red
end

-- Function to release Redis connection back to the connection pool
local function release_redis(red, idle_timeout, pool_size)
    if not red then return end
    
    local ok, err = red:set_keepalive(idle_timeout, pool_size)
    if not ok then
        utils.log(ngx.ERR, "Failed to set Redis keepalive: " .. (err or "unknown error"))
    end
end

-- Function to record API call statistics
function _M.record_api_call(api_name, status_code, response_time, error_message, api_path)
    -- Get Redis configuration
    local redis_host = os.getenv("REDIS_HOST")
    local redis_port = tonumber(os.getenv("REDIS_PORT") or 6379)
    local redis_password = os.getenv("REDIS_PASSWORD") or nil
    local redis_timeout = tonumber(os.getenv("REDIS_TIMEOUT") or 1000)
    local redis_pool_size = tonumber(os.getenv("REDIS_POOL_SIZE") or 100)
    local redis_pool_idle_timeout = tonumber(os.getenv("REDIS_POOL_IDLE_TIMEOUT") or 10000)
    
    -- Get Redis connection
    local red, err = get_redis(redis_host, redis_port, redis_password, redis_timeout)
    if not red then
        utils.log(ngx.ERR, "Failed to connect to Redis for stats recording: " .. (err or "unknown error"))
        return
    end
    
    -- Get current time
    local current_time = ngx.time()
    local date_str = os.date("%Y-%m-%d", current_time)
    local hour_str = os.date("%Y-%m-%d-%H", current_time)
    
    -- Determine if the call was successful
    local is_success = status_code and status_code >= 200 and status_code < 400
    
    -- Create keys for Redis - API level
    local total_key = STATS_PREFIX .. api_name .. ":total"
    local success_key = STATS_PREFIX .. api_name .. ":success"
    local failure_key = STATS_PREFIX .. api_name .. ":failure"
    local status_key = STATS_PREFIX .. api_name .. ":status:" .. (status_code or "unknown")
    local response_time_key = STATS_PREFIX .. api_name .. ":response_time"
    local error_key = STATS_PREFIX .. api_name .. ":errors"
    
    -- Daily keys - API level
    local daily_total_key = DAILY_STATS_PREFIX .. api_name .. ":" .. date_str .. ":total"
    local daily_success_key = DAILY_STATS_PREFIX .. api_name .. ":" .. date_str .. ":success"
    local daily_failure_key = DAILY_STATS_PREFIX .. api_name .. ":" .. date_str .. ":failure"
    local daily_status_key = DAILY_STATS_PREFIX .. api_name .. ":" .. date_str .. ":status:" .. (status_code or "unknown")
    local daily_response_time_key = DAILY_STATS_PREFIX .. api_name .. ":" .. date_str .. ":response_time"
    
    -- Hourly keys - API level
    local hourly_total_key = HOURLY_STATS_PREFIX .. api_name .. ":" .. hour_str .. ":total"
    local hourly_success_key = HOURLY_STATS_PREFIX .. api_name .. ":" .. hour_str .. ":success"
    local hourly_failure_key = HOURLY_STATS_PREFIX .. api_name .. ":" .. hour_str .. ":failure"
    local hourly_status_key = HOURLY_STATS_PREFIX .. api_name .. ":" .. hour_str .. ":status:" .. (status_code or "unknown")
    local hourly_response_time_key = HOURLY_STATS_PREFIX .. api_name .. ":" .. hour_str .. ":response_time"
    
    -- Start Redis pipeline for better performance
    red:init_pipeline()
    
    -- Increment total calls - API level
    red:incr(total_key)
    red:incr(daily_total_key)
    red:incr(hourly_total_key)
    
    -- Set expiry for daily and hourly stats - API level
    red:expire(daily_total_key, 86400 * 30)  -- Keep daily stats for 30 days
    red:expire(hourly_total_key, 86400 * 7)  -- Keep hourly stats for 7 days
    
    -- Increment success or failure counters - API level
    if is_success then
        red:incr(success_key)
        red:incr(daily_success_key)
        red:incr(hourly_success_key)
        red:expire(daily_success_key, 86400 * 30)
        red:expire(hourly_success_key, 86400 * 7)
    else
        red:incr(failure_key)
        red:incr(daily_failure_key)
        red:incr(hourly_failure_key)
        red:expire(daily_failure_key, 86400 * 30)
        red:expire(hourly_failure_key, 86400 * 7)
    end
    
    -- Increment status code counter - API level
    red:incr(status_key)
    red:incr(daily_status_key)
    red:incr(hourly_status_key)
    red:expire(daily_status_key, 86400 * 30)
    red:expire(hourly_status_key, 86400 * 7)
    
    -- Record response time - API level
    if response_time then
        -- Add to sorted set for percentile calculations
        red:zadd(response_time_key, response_time, current_time .. ":" .. math.random(1000000))
        red:zadd(daily_response_time_key, response_time, current_time .. ":" .. math.random(1000000))
        red:zadd(hourly_response_time_key, response_time, current_time .. ":" .. math.random(1000000))
        
        -- Trim sorted sets to prevent unbounded growth
        red:zremrangebyrank(response_time_key, 0, -10001)  -- Keep last 10000 entries
        red:expire(daily_response_time_key, 86400 * 30)
        red:expire(hourly_response_time_key, 86400 * 7)
    end
    
    -- Record error message if present - API level
    if error_message and not is_success then
        local error_json = cjson.encode({
            time = current_time,
            status = status_code,
            message = error_message
        })
        red:lpush(error_key, error_json)
        red:ltrim(error_key, 0, 999)  -- Keep last 1000 errors
    end
    
    -- If path is provided, record path-level statistics
    if api_path and api_path ~= "" then
        -- Normalize the path - remove trailing slash and ensure it starts with /
        if api_path:sub(1, 1) ~= "/" then
            api_path = "/" .. api_path
        end
        
        -- Create a path identifier
        local path_id = api_name .. ":path:" .. api_path
        
        -- Create keys for Redis - Path level
        local path_total_key = STATS_PREFIX .. path_id .. ":total"
        local path_success_key = STATS_PREFIX .. path_id .. ":success"
        local path_failure_key = STATS_PREFIX .. path_id .. ":failure"
        local path_status_key = STATS_PREFIX .. path_id .. ":status:" .. (status_code or "unknown")
        local path_response_time_key = STATS_PREFIX .. path_id .. ":response_time"
        local path_error_key = STATS_PREFIX .. path_id .. ":errors"
        
        -- Daily keys - Path level
        local path_daily_total_key = DAILY_STATS_PREFIX .. path_id .. ":" .. date_str .. ":total"
        local path_daily_success_key = DAILY_STATS_PREFIX .. path_id .. ":" .. date_str .. ":success"
        local path_daily_failure_key = DAILY_STATS_PREFIX .. path_id .. ":" .. date_str .. ":failure"
        local path_daily_status_key = DAILY_STATS_PREFIX .. path_id .. ":" .. date_str .. ":status:" .. (status_code or "unknown")
        local path_daily_response_time_key = DAILY_STATS_PREFIX .. path_id .. ":" .. date_str .. ":response_time"
        
        -- Hourly keys - Path level
        local path_hourly_total_key = HOURLY_STATS_PREFIX .. path_id .. ":" .. hour_str .. ":total"
        local path_hourly_success_key = HOURLY_STATS_PREFIX .. path_id .. ":" .. hour_str .. ":success"
        local path_hourly_failure_key = HOURLY_STATS_PREFIX .. path_id .. ":" .. hour_str .. ":failure"
        local path_hourly_status_key = HOURLY_STATS_PREFIX .. path_id .. ":" .. hour_str .. ":status:" .. (status_code or "unknown")
        local path_hourly_response_time_key = HOURLY_STATS_PREFIX .. path_id .. ":" .. hour_str .. ":response_time"
        
        -- Increment total calls - Path level
        red:incr(path_total_key)
        red:incr(path_daily_total_key)
        red:incr(path_hourly_total_key)
        
        -- Set expiry for daily and hourly stats - Path level
        red:expire(path_daily_total_key, 86400 * 30)  -- Keep daily stats for 30 days
        red:expire(path_hourly_total_key, 86400 * 7)  -- Keep hourly stats for 7 days
        
        -- Increment success or failure counters - Path level
        if is_success then
            red:incr(path_success_key)
            red:incr(path_daily_success_key)
            red:incr(path_hourly_success_key)
            red:expire(path_daily_success_key, 86400 * 30)
            red:expire(path_hourly_success_key, 86400 * 7)
        else
            red:incr(path_failure_key)
            red:incr(path_daily_failure_key)
            red:incr(path_hourly_failure_key)
            red:expire(path_daily_failure_key, 86400 * 30)
            red:expire(path_hourly_failure_key, 86400 * 7)
        end
        
        -- Increment status code counter - Path level
        red:incr(path_status_key)
        red:incr(path_daily_status_key)
        red:incr(path_hourly_status_key)
        red:expire(path_daily_status_key, 86400 * 30)
        red:expire(path_hourly_status_key, 86400 * 7)
        
        -- Record response time - Path level
        if response_time then
            -- Add to sorted set for percentile calculations
            red:zadd(path_response_time_key, response_time, current_time .. ":" .. math.random(1000000))
            red:zadd(path_daily_response_time_key, response_time, current_time .. ":" .. math.random(1000000))
            red:zadd(path_hourly_response_time_key, response_time, current_time .. ":" .. math.random(1000000))
            
            -- Trim sorted sets to prevent unbounded growth
            red:zremrangebyrank(path_response_time_key, 0, -10001)  -- Keep last 10000 entries
            red:expire(path_daily_response_time_key, 86400 * 30)
            red:expire(path_hourly_response_time_key, 86400 * 7)
        end
        
        -- Record error message if present - Path level
        if error_message and not is_success then
            local error_json = cjson.encode({
                time = current_time,
                status = status_code,
                message = error_message
            })
            red:lpush(path_error_key, error_json)
            red:ltrim(path_error_key, 0, 999)  -- Keep last 1000 errors
        end
        
        -- Add this path to the list of paths for this API
        red:sadd(STATS_PREFIX .. api_name .. ":paths", api_path)
    end
    
    -- Execute pipeline
    local results, err = red:commit_pipeline()
    if not results then
        utils.log(ngx.ERR, "Failed to record API stats: " .. (err or "unknown error"))
    end
    
    -- Release Redis connection
    release_redis(red, redis_pool_idle_timeout, redis_pool_size)
end

-- Function to get API statistics
function _M.get_api_stats(api_name, period)
    -- Get Redis configuration
    local redis_host = os.getenv("REDIS_HOST")
    local redis_port = tonumber(os.getenv("REDIS_PORT") or 6379)
    local redis_password = os.getenv("REDIS_PASSWORD") or nil
    local redis_timeout = tonumber(os.getenv("REDIS_TIMEOUT") or 1000)
    local redis_pool_size = tonumber(os.getenv("REDIS_POOL_SIZE") or 100)
    local redis_pool_idle_timeout = tonumber(os.getenv("REDIS_POOL_IDLE_TIMEOUT") or 10000)
    
    -- Get Redis connection
    local red, err = get_redis(redis_host, redis_port, redis_password, redis_timeout)
    if not red then
        utils.log(ngx.ERR, "Failed to connect to Redis for stats retrieval: " .. (err or "unknown error"))
        return nil, "Failed to connect to Redis"
    end
    
    local stats = {}
    local prefix
    
    -- Determine which prefix to use based on period
    if period == "daily" then
        prefix = DAILY_STATS_PREFIX
        -- Get list of dates with data
        local keys = red:keys(prefix .. api_name .. ":*")
        local dates = {}
        for _, key in ipairs(keys) do
            local date = key:match(prefix .. api_name .. ":([%d-]+)")
            if date and not dates[date] then
                dates[date] = true
            end
        end
        
        -- Convert to array
        stats.dates = {}
        for date in pairs(dates) do
            table.insert(stats.dates, date)
        end
        table.sort(stats.dates)
        
    elseif period == "hourly" then
        prefix = HOURLY_STATS_PREFIX
        -- Get list of hours with data
        local keys = red:keys(prefix .. api_name .. ":*")
        local hours = {}
        for _, key in ipairs(keys) do
            local hour = key:match(prefix .. api_name .. ":([%d-]+)")
            if hour and not hours[hour] then
                hours[hour] = true
            end
        end
        
        -- Convert to array
        stats.hours = {}
        for hour in pairs(hours) do
            table.insert(stats.hours, hour)
        end
        table.sort(stats.hours)
        
    else
        -- Default to all-time stats
        prefix = STATS_PREFIX
        
        -- Get total calls
        stats.total = tonumber(red:get(prefix .. api_name .. ":total")) or 0
        stats.success = tonumber(red:get(prefix .. api_name .. ":success")) or 0
        stats.failure = tonumber(red:get(prefix .. api_name .. ":failure")) or 0
        
        -- Get status code counts
        stats.status_codes = {}
        local status_keys = red:keys(prefix .. api_name .. ":status:*")
        for _, key in ipairs(status_keys) do
            local status = key:match(":status:(%d+)")
            if status then
                stats.status_codes[status] = tonumber(red:get(key)) or 0
            end
        end
        
        -- Get response time percentiles
        local response_time_key = prefix .. api_name .. ":response_time"
        local count = red:zcard(response_time_key)
        
        if count > 0 then
            stats.response_time = {
                count = count
            }
            
            -- Calculate percentiles
            local p50_index = math.ceil(count * 0.5)
            local p90_index = math.ceil(count * 0.9)
            local p95_index = math.ceil(count * 0.95)
            local p99_index = math.ceil(count * 0.99)
            
            local p50 = red:zrange(response_time_key, p50_index - 1, p50_index - 1, "WITHSCORES")
            local p90 = red:zrange(response_time_key, p90_index - 1, p90_index - 1, "WITHSCORES")
            local p95 = red:zrange(response_time_key, p95_index - 1, p95_index - 1, "WITHSCORES")
            local p99 = red:zrange(response_time_key, p99_index - 1, p99_index - 1, "WITHSCORES")
            
            if p50 and #p50 >= 2 then stats.response_time.p50 = tonumber(p50[2]) end
            if p90 and #p90 >= 2 then stats.response_time.p90 = tonumber(p90[2]) end
            if p95 and #p95 >= 2 then stats.response_time.p95 = tonumber(p95[2]) end
            if p99 and #p99 >= 2 then stats.response_time.p99 = tonumber(p99[2]) end
            
            -- Get min and max
            local min = red:zrange(response_time_key, 0, 0, "WITHSCORES")
            local max = red:zrange(response_time_key, -1, -1, "WITHSCORES")
            
            if min and #min >= 2 then stats.response_time.min = tonumber(min[2]) end
            if max and #max >= 2 then stats.response_time.max = tonumber(max[2]) end
        end
        
        -- Get recent errors
        local error_key = prefix .. api_name .. ":errors"
        local errors = red:lrange(error_key, 0, 9)  -- Get last 10 errors
        
        if errors and #errors > 0 then
            stats.recent_errors = {}
            for _, error_json in ipairs(errors) do
                local success, error_data = pcall(cjson.decode, error_json)
                if success then
                    table.insert(stats.recent_errors, error_data)
                end
            end
        end
    end
    
    -- Release Redis connection
    release_redis(red, redis_pool_idle_timeout, redis_pool_size)
    
    return stats
end

-- Function to get all API names
function _M.get_api_names()
    -- Get Redis configuration
    local redis_host = os.getenv("REDIS_HOST")
    local redis_port = tonumber(os.getenv("REDIS_PORT") or 6379)
    local redis_password = os.getenv("REDIS_PASSWORD") or nil
    local redis_timeout = tonumber(os.getenv("REDIS_TIMEOUT") or 1000)
    local redis_pool_size = tonumber(os.getenv("REDIS_POOL_SIZE") or 100)
    local redis_pool_idle_timeout = tonumber(os.getenv("REDIS_POOL_IDLE_TIMEOUT") or 10000)
    
    -- Get Redis connection
    local red, err = get_redis(redis_host, redis_port, redis_password, redis_timeout)
    if not red then
        utils.log(ngx.ERR, "Failed to connect to Redis for API names retrieval: " .. (err or "unknown error"))
        return {}
    end
    
    -- Get all keys matching the API stats pattern
    local keys = red:keys(STATS_PREFIX .. "*:total")
    
    -- Extract API names from keys
    local api_names = {}
    for _, key in ipairs(keys) do
        local api_name = key:match(STATS_PREFIX .. "([^:]+):total")
        if api_name and not api_name:match("^path:") then
            table.insert(api_names, api_name)
        end
    end
    
    -- Release Redis connection
    release_redis(red, redis_pool_idle_timeout, redis_pool_size)
    
    return api_names
end

-- Function to get all paths for an API
function _M.get_api_paths(api_name)
    -- Get Redis configuration
    local redis_host = os.getenv("REDIS_HOST")
    local redis_port = tonumber(os.getenv("REDIS_PORT") or 6379)
    local redis_password = os.getenv("REDIS_PASSWORD") or nil
    local redis_timeout = tonumber(os.getenv("REDIS_TIMEOUT") or 1000)
    local redis_pool_size = tonumber(os.getenv("REDIS_POOL_SIZE") or 100)
    local redis_pool_idle_timeout = tonumber(os.getenv("REDIS_POOL_IDLE_TIMEOUT") or 10000)
    
    -- Get Redis connection
    local red, err = get_redis(redis_host, redis_port, redis_password, redis_timeout)
    if not red then
        utils.log(ngx.ERR, "Failed to connect to Redis for API paths retrieval: " .. (err or "unknown error"))
        return {}
    end
    
    -- Get all paths for this API
    local paths = red:smembers(STATS_PREFIX .. api_name .. ":paths")
    
    -- Release Redis connection
    release_redis(red, redis_pool_idle_timeout, redis_pool_size)
    
    return paths or {}
end

-- Function to get path statistics
function _M.get_path_stats(api_name, path, period)
    -- Get Redis configuration
    local redis_host = os.getenv("REDIS_HOST")
    local redis_port = tonumber(os.getenv("REDIS_PORT") or 6379)
    local redis_password = os.getenv("REDIS_PASSWORD") or nil
    local redis_timeout = tonumber(os.getenv("REDIS_TIMEOUT") or 1000)
    local redis_pool_size = tonumber(os.getenv("REDIS_POOL_SIZE") or 100)
    local redis_pool_idle_timeout = tonumber(os.getenv("REDIS_POOL_IDLE_TIMEOUT") or 10000)
    
    -- Get Redis connection
    local red, err = get_redis(redis_host, redis_port, redis_password, redis_timeout)
    if not red then
        utils.log(ngx.ERR, "Failed to connect to Redis for path stats retrieval: " .. (err or "unknown error"))
        return nil, "Failed to connect to Redis"
    end
    
    -- Create a path identifier
    local path_id = api_name .. ":path:" .. path
    
    local stats = {}
    local prefix
    
    -- Determine which prefix to use based on period
    if period == "daily" then
        prefix = DAILY_STATS_PREFIX
        -- Get list of dates with data
        local keys = red:keys(prefix .. path_id .. ":*")
        local dates = {}
        for _, key in ipairs(keys) do
            local date = key:match(prefix .. path_id .. ":([%d-]+)")
            if date and not dates[date] then
                dates[date] = true
            end
        end
        
        -- Convert to array
        stats.dates = {}
        for date in pairs(dates) do
            table.insert(stats.dates, date)
        end
        table.sort(stats.dates)
        
    elseif period == "hourly" then
        prefix = HOURLY_STATS_PREFIX
        -- Get list of hours with data
        local keys = red:keys(prefix .. path_id .. ":*")
        local hours = {}
        for _, key in ipairs(keys) do
            local hour = key:match(prefix .. path_id .. ":([%d-]+)")
            if hour and not hours[hour] then
                hours[hour] = true
            end
        end
        
        -- Convert to array
        stats.hours = {}
        for hour in pairs(hours) do
            table.insert(stats.hours, hour)
        end
        table.sort(stats.hours)
        
    else
        -- Default to all-time stats
        prefix = STATS_PREFIX
        
        -- Get total calls
        stats.total = tonumber(red:get(prefix .. path_id .. ":total")) or 0
        stats.success = tonumber(red:get(prefix .. path_id .. ":success")) or 0
        stats.failure = tonumber(red:get(prefix .. path_id .. ":failure")) or 0
        
        -- Get status code counts
        stats.status_codes = {}
        local status_keys = red:keys(prefix .. path_id .. ":status:*")
        for _, key in ipairs(status_keys) do
            local status = key:match(":status:(%d+)")
            if status then
                stats.status_codes[status] = tonumber(red:get(key)) or 0
            end
        end
        
        -- Get response time percentiles
        local response_time_key = prefix .. path_id .. ":response_time"
        local count = red:zcard(response_time_key)
        
        if count > 0 then
            stats.response_time = {
                count = count
            }
            
            -- Calculate percentiles
            local p50_index = math.ceil(count * 0.5)
            local p90_index = math.ceil(count * 0.9)
            local p95_index = math.ceil(count * 0.95)
            local p99_index = math.ceil(count * 0.99)
            
            local p50 = red:zrange(response_time_key, p50_index - 1, p50_index - 1, "WITHSCORES")
            local p90 = red:zrange(response_time_key, p90_index - 1, p90_index - 1, "WITHSCORES")
            local p95 = red:zrange(response_time_key, p95_index - 1, p95_index - 1, "WITHSCORES")
            local p99 = red:zrange(response_time_key, p99_index - 1, p99_index - 1, "WITHSCORES")
            
            if p50 and #p50 >= 2 then stats.response_time.p50 = tonumber(p50[2]) end
            if p90 and #p90 >= 2 then stats.response_time.p90 = tonumber(p90[2]) end
            if p95 and #p95 >= 2 then stats.response_time.p95 = tonumber(p95[2]) end
            if p99 and #p99 >= 2 then stats.response_time.p99 = tonumber(p99[2]) end
            
            -- Get min and max
            local min = red:zrange(response_time_key, 0, 0, "WITHSCORES")
            local max = red:zrange(response_time_key, -1, -1, "WITHSCORES")
            
            if min and #min >= 2 then stats.response_time.min = tonumber(min[2]) end
            if max and #max >= 2 then stats.response_time.max = tonumber(max[2]) end
        end
        
        -- Get recent errors
        local error_key = prefix .. path_id .. ":errors"
        local errors = red:lrange(error_key, 0, 9)  -- Get last 10 errors
        
        if errors and #errors > 0 then
            stats.recent_errors = {}
            for _, error_json in ipairs(errors) do
                local success, error_data = pcall(cjson.decode, error_json)
                if success then
                    table.insert(stats.recent_errors, error_data)
                end
            end
        end
    end
    
    -- Release Redis connection
    release_redis(red, redis_pool_idle_timeout, redis_pool_size)
    
    return stats
end

return _M 