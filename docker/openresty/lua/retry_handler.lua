local _M = {}

-- Default retry configuration
_M.DEFAULT_CONFIG = {
    max_attempts = 3,           -- Maximum number of retry attempts
    initial_delay = 1,          -- Initial delay in seconds
    max_delay = 10,             -- Maximum delay in seconds
    backoff_factor = 2,         -- Exponential backoff multiplier
    retry_on_status = {         -- HTTP status codes to retry on
        500, 502, 503, 504, 429 -- Server errors and rate limiting
    },
    retry_on_errors = {         -- Connection errors to retry on
        "timeout",
        "connection refused",
        "connection reset",
        "socket", 
        "host not found"
    }
}

-- Function to check if retry is needed based on status code
function _M.should_retry_status(status_code, config)
    if not status_code then return false end
    
    for _, retry_status in ipairs(config.retry_on_status) do
        if status_code == retry_status then
            return true
        end
    end
    
    return false
end

-- Function to check if retry is needed based on error message
function _M.should_retry_error(err, config)
    if not err then return false end
    
    for _, retry_error in ipairs(config.retry_on_errors) do
        if string.find(string.lower(err), string.lower(retry_error)) then
            return true
        end
    end
    
    return false
end

-- Calculate delay with exponential backoff
function _M.calculate_delay(attempt, config)
    local delay = config.initial_delay * (config.backoff_factor ^ (attempt - 1))
    -- Add some jitter (±20%) to prevent thundering herd
    local jitter = delay * (0.8 + math.random() * 0.4)
    -- Cap at max_delay
    return math.min(jitter, config.max_delay)
end

-- Sleep function
function _M.sleep(seconds)
    ngx.sleep(seconds)
end

-- Main retry function
function _M.with_retries(func, config)
    config = config or _M.DEFAULT_CONFIG
    
    local attempt = 1
    local max_attempts = config.max_attempts or _M.DEFAULT_CONFIG.max_attempts
    
    -- Log start of retry process
    ngx.log(ngx.INFO, "Starting request with retry configuration: max_attempts=" .. max_attempts)
    
    while attempt <= max_attempts do
        local start_time = ngx.now()
        local result = {func()} -- Capture all return values
        local request_time = ngx.now() - start_time
        
        -- Check if we need to retry
        local success = result[1]
        local err = result[3] -- Assuming error is the third return value
        local status_code = result[2] -- Assuming status code is the second return value
        
        -- Log attempt details
        if success then
            ngx.log(ngx.INFO, "Request succeeded on attempt " .. attempt .. "/" .. max_attempts .. 
                             " with status " .. (status_code or "nil") .. 
                             " (request time: " .. string.format("%.3f", request_time) .. "s)")
        else
            ngx.log(ngx.WARN, "Request failed on attempt " .. attempt .. "/" .. max_attempts .. 
                             " with status " .. (status_code or "nil") .. 
                             " and error " .. (err or "nil") ..
                             " (request time: " .. string.format("%.3f", request_time) .. "s)")
        end
        
        if success or 
           (not _M.should_retry_status(status_code, config) and 
            not _M.should_retry_error(err, config)) or 
           attempt == max_attempts then
            -- Return all original results if successful or we've reached max attempts
            if not success and attempt == max_attempts then
                ngx.log(ngx.ERR, "Request failed permanently after " .. max_attempts .. " attempts")
            end
            return unpack(result)
        end
        
        -- Calculate delay with exponential backoff
        local delay = _M.calculate_delay(attempt, config)
        
        -- Log retry attempt
        ngx.log(ngx.WARN, "Retrying in " .. string.format("%.2f", delay) .. " seconds (attempt " .. 
                          attempt .. "/" .. max_attempts .. ")")
        
        -- Sleep before retry
        _M.sleep(delay)
        
        -- Increment attempt counter
        attempt = attempt + 1
    end
end

return _M 