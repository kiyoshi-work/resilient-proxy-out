local _M = {}

-- Circuit breaker states
_M.STATE_CLOSED = "CLOSED"       -- Normal operation, requests flow through
_M.STATE_OPEN = "OPEN"           -- Circuit is open, requests are rejected
_M.STATE_HALF_OPEN = "HALF_OPEN" -- Testing if service is back online

-- Circuit breaker configuration
local DEFAULT_CONFIG = {
    failure_threshold = 5,        -- Number of failures before opening circuit
    reset_timeout = 30,           -- Seconds to wait before trying half-open state
    request_timeout = 10000,      -- Request timeout in ms
    success_threshold = 2         -- Number of successful requests to close circuit
}

-- Initialize the circuit breaker
function _M.init(target, config)
    local circuit_breaker = ngx.shared.circuit_breaker
    local cb_key = "cb:" .. target
    
    -- Check if circuit breaker is already initialized
    local state = circuit_breaker:get(cb_key .. ":state")
    if not state then
        -- Initialize circuit breaker state
        circuit_breaker:set(cb_key .. ":state", _M.STATE_CLOSED)
        circuit_breaker:set(cb_key .. ":failures", 0)
        circuit_breaker:set(cb_key .. ":successes", 0)
        circuit_breaker:set(cb_key .. ":last_failure_time", 0)
        
        -- Store configuration
        config = config or DEFAULT_CONFIG
        circuit_breaker:set(cb_key .. ":failure_threshold", config.failure_threshold or DEFAULT_CONFIG.failure_threshold)
        circuit_breaker:set(cb_key .. ":reset_timeout", config.reset_timeout or DEFAULT_CONFIG.reset_timeout)
        circuit_breaker:set(cb_key .. ":request_timeout", config.request_timeout or DEFAULT_CONFIG.request_timeout)
        circuit_breaker:set(cb_key .. ":success_threshold", config.success_threshold or DEFAULT_CONFIG.success_threshold)
        
        ngx.log(ngx.INFO, "Circuit breaker initialized for target: " .. target)
    end
    
    return cb_key
end

-- Get current circuit state
function _M.get_state(cb_key)
    local circuit_breaker = ngx.shared.circuit_breaker
    local state = circuit_breaker:get(cb_key .. ":state")
    
    -- Check if we need to transition from OPEN to HALF_OPEN
    if state == _M.STATE_OPEN then
        local last_failure_time = circuit_breaker:get(cb_key .. ":last_failure_time")
        local reset_timeout = circuit_breaker:get(cb_key .. ":reset_timeout")
        local current_time = ngx.time()
        
        if current_time - last_failure_time >= reset_timeout then
            -- Transition to HALF_OPEN state
            circuit_breaker:set(cb_key .. ":state", _M.STATE_HALF_OPEN)
            circuit_breaker:set(cb_key .. ":successes", 0)
            ngx.log(ngx.INFO, "Circuit transitioned from OPEN to HALF_OPEN for " .. cb_key)
            return _M.STATE_HALF_OPEN
        end
    end
    
    return state
end

-- Record a successful request
function _M.record_success(cb_key)
    local circuit_breaker = ngx.shared.circuit_breaker
    local state = _M.get_state(cb_key)
    
    if state == _M.STATE_HALF_OPEN then
        local successes = circuit_breaker:incr(cb_key .. ":successes", 1)
        local success_threshold = circuit_breaker:get(cb_key .. ":success_threshold")
        
        if successes >= success_threshold then
            -- Transition back to CLOSED state
            circuit_breaker:set(cb_key .. ":state", _M.STATE_CLOSED)
            circuit_breaker:set(cb_key .. ":failures", 0)
            ngx.log(ngx.INFO, "Circuit closed after " .. successes .. " successful requests for " .. cb_key)
        end
    elseif state == _M.STATE_CLOSED then
        -- Reset failure count on success in closed state
        circuit_breaker:set(cb_key .. ":failures", 0)
    end
end

-- Record a failed request
function _M.record_failure(cb_key)
    local circuit_breaker = ngx.shared.circuit_breaker
    local state = _M.get_state(cb_key)
    
    if state == _M.STATE_CLOSED then
        local failures = circuit_breaker:incr(cb_key .. ":failures", 1)
        local failure_threshold = circuit_breaker:get(cb_key .. ":failure_threshold")
        
        if failures >= failure_threshold then
            -- Open the circuit
            circuit_breaker:set(cb_key .. ":state", _M.STATE_OPEN)
            circuit_breaker:set(cb_key .. ":last_failure_time", ngx.time())
            ngx.log(ngx.WARN, "Circuit opened after " .. failures .. " consecutive failures for " .. cb_key)
        end
    elseif state == _M.STATE_HALF_OPEN then
        -- Any failure in half-open state opens the circuit again
        circuit_breaker:set(cb_key .. ":state", _M.STATE_OPEN)
        circuit_breaker:set(cb_key .. ":last_failure_time", ngx.time())
        ngx.log(ngx.WARN, "Circuit re-opened after failure in half-open state for " .. cb_key)
    end
end

-- Check if a request should be allowed through
function _M.allow_request(cb_key)
    local state = _M.get_state(cb_key)
    
    if state == _M.STATE_CLOSED then
        return true
    elseif state == _M.STATE_HALF_OPEN then
        -- In half-open state, we allow a limited number of requests through
        return true
    else
        -- In open state, we reject all requests
        return false
    end
end

-- Get time until circuit reset (for open circuit)
function _M.time_to_reset(cb_key)
    local circuit_breaker = ngx.shared.circuit_breaker
    local state = circuit_breaker:get(cb_key .. ":state")
    
    if state == _M.STATE_OPEN then
        local last_failure_time = circuit_breaker:get(cb_key .. ":last_failure_time")
        local reset_timeout = circuit_breaker:get(cb_key .. ":reset_timeout")
        local current_time = ngx.time()
        local time_left = reset_timeout - (current_time - last_failure_time)
        
        return math.max(0, time_left)
    end
    
    return 0
end

return _M 