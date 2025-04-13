local utils = require "utils"
local circuit_breaker = require "circuit_breaker"

-- Function to get all circuit breaker keys
local function get_all_circuit_keys()
    local circuit_breaker_dict = ngx.shared.circuit_breaker
    local keys = circuit_breaker_dict:get_keys()
    
    -- Filter to get only the base keys (those ending with ":state")
    local circuit_keys = {}
    for _, key in ipairs(keys) do
        if key:match(":state$") then
            local base_key = key:gsub(":state$", "")
            table.insert(circuit_keys, base_key)
        end
    end
    
    return circuit_keys
end

-- Function to get circuit breaker status for a specific key
local function get_circuit_status(cb_key)
    local circuit_breaker_dict = ngx.shared.circuit_breaker
    
    -- Get circuit breaker state and configuration
    local state = circuit_breaker_dict:get(cb_key .. ":state")
    if not state then
        return nil
    end
    
    local failures = circuit_breaker_dict:get(cb_key .. ":failures") or 0
    local successes = circuit_breaker_dict:get(cb_key .. ":successes") or 0
    local last_failure_time = circuit_breaker_dict:get(cb_key .. ":last_failure_time") or 0
    local failure_threshold = circuit_breaker_dict:get(cb_key .. ":failure_threshold") or 5
    local reset_timeout = circuit_breaker_dict:get(cb_key .. ":reset_timeout") or 30
    local success_threshold = circuit_breaker_dict:get(cb_key .. ":success_threshold") or 2
    
    -- Calculate time to reset if circuit is open
    local time_to_reset = 0
    if state == circuit_breaker.STATE_OPEN then
        local current_time = ngx.time()
        time_to_reset = math.max(0, reset_timeout - (current_time - last_failure_time))
    end
    
    -- Extract target name from the key
    local target = cb_key:gsub("^cb:", "")
    
    return {
        target = target,
        state = state,
        failures = failures,
        successes = successes,
        last_failure_time = last_failure_time,
        time_to_reset = time_to_reset,
        config = {
            failure_threshold = failure_threshold,
            reset_timeout = reset_timeout,
            success_threshold = success_threshold
        }
    }
end

-- Main function to handle the request
local function main()
    -- Get all circuit breaker keys
    local circuit_keys = get_all_circuit_keys()
    
    -- Get status for each circuit
    local circuit_statuses = {}
    for _, cb_key in ipairs(circuit_keys) do
        local status = get_circuit_status(cb_key)
        if status then
            table.insert(circuit_statuses, status)
        end
    end
    
    -- Return the response
    utils.json_response({
        timestamp = ngx.time(),
        circuits = circuit_statuses
    })
end

-- Execute the main function
main() 