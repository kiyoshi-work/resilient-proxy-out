local http = require "resty.http"
local cjson = require "cjson"
local utils = require "utils"
local redis = require "resty.redis"
local circuit_breaker = require "circuit_breaker"
local api_config = require "api_config"
local retry_handler = require "retry_handler"
local api_stats = require "api_stats"

-- Main function
local function main()
    -- Get API name and path from nginx variables
    local api_name = ngx.var.api_name
    local api_path = ngx.var.api_path or ""
    
    -- Get request method
    local request_method = ngx.req.get_method()
    
    -- Get request headers
    local request_headers = ngx.req.get_headers()
    
    -- Get request body
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    
    -- Get query parameters
    local query_params = ngx.req.get_uri_args()
    
    -- Get API configuration
    local config = api_config.get_config(api_name)
    if not config then
        utils.json_response({
            error = "Unknown API: " .. api_name
        }, 404)
        return
    end
    
    -- Validate request
    if config.requires_body and (not body or body == "") then
        utils.json_response({
            error = "Request body is required"
        }, 400)
        return
    end
    
    -- Validate JSON if body is present and content-type is application/json
    local request_data
    if body and body ~= "" and 
       request_headers["content-type"] and 
       request_headers["content-type"]:find("application/json") then
        local err
        request_data, err = utils.parse_json(body)
        if not request_data then
            utils.json_response({
                error = "Invalid JSON in request body: " .. (err or "unknown error")
            }, 400)
            return
        end
    end
    
    -- Make the proxied request
    local response_data, status_code, response_headers, request_err = make_proxied_request(
        api_name, 
        config, 
        body, 
        api_path, 
        request_method, 
        request_headers,
        query_params
    )
    
    -- Handle errors
    if not response_data then
        utils.json_response({
            error = request_err or "Unknown error occurred"
        }, status_code or 500)
        return
    end
    
    -- Set response headers if any
    if response_headers then
        for k, v in pairs(response_headers) do
            -- Skip certain headers that nginx will set
            if k ~= "server" and k ~= "date" and k ~= "content-length" then
                ngx.header[k] = v
            end
        end
    end
    
    -- Return the response
    utils.json_response(response_data, status_code)
end

-- Function to make the proxied request
function make_proxied_request(api_name, config, body, api_path, request_method, request_headers, query_params)
    -- Initialize circuit breaker for this API
    local cb_key = circuit_breaker.init(config.target_url, config.circuit_breaker or {})
    
    -- Add this line to track the start time for the entire request
    local start_time = ngx.now()
    
    -- Check if circuit is open
    if not circuit_breaker.allow_request(cb_key) then
        local time_left = circuit_breaker.time_to_reset(cb_key)
        utils.log(ngx.WARN, "Circuit is open for " .. api_name .. ", rejecting request. Will try again in " .. time_left .. " seconds")
        return nil, 503, nil, "Service temporarily unavailable. Please try again in " .. time_left .. " seconds"
    end
    
    -- Get Redis configuration
    local redis_host = os.getenv("REDIS_HOST")
    local redis_port = tonumber(os.getenv("REDIS_PORT") or 6379)
    local redis_password = os.getenv("REDIS_PASSWORD") or nil
    local redis_timeout = tonumber(os.getenv("REDIS_TIMEOUT") or 1000)
    local redis_pool_size = tonumber(os.getenv("REDIS_POOL_SIZE") or 100)
    local redis_pool_idle_timeout = tonumber(os.getenv("REDIS_POOL_IDLE_TIMEOUT") or 10000)
    local cache_ttl = config.cache_ttl or tonumber(os.getenv("CACHE_TTL") or 60)
    
    -- Generate a cache key based on all request parameters
    local cache_key
    local red
    
    if config.enable_cache then
        -- Create a comprehensive cache key that includes all request details
        local cache_key_parts = {
            api_name,
            api_path,
            request_method
        }
        
        -- Add sorted query parameters to cache key
        local sorted_query_keys = {}
        for k in pairs(query_params) do
            table.insert(sorted_query_keys, k)
        end
        table.sort(sorted_query_keys)
        
        for _, k in ipairs(sorted_query_keys) do
            table.insert(cache_key_parts, k .. "=" .. tostring(query_params[k]))
        end
        
        -- Add relevant headers to cache key
        if config.cache_headers then
            -- Different header inclusion strategies
            if config.cache_header_strategy == "all" then
                -- Include all headers (not recommended)
                for k, v in pairs(request_headers) do
                    table.insert(cache_key_parts, k .. "=" .. v)
                end
            elseif config.cache_header_strategy == "none" then
                -- Don't include any headers
            else
                -- Default: include only specified headers
                for _, header_name in ipairs(config.cache_headers) do
                    if request_headers[header_name] then
                        table.insert(cache_key_parts, header_name .. "=" .. request_headers[header_name])
                    end
                end
            end
        end
        
        -- Add body to cache key if present
        if body and body ~= "" then
            table.insert(cache_key_parts, ngx.md5(body))
        end
        
        -- Create the final cache key
        cache_key = "api_cache:" .. table.concat(cache_key_parts, ":")
        
        -- Get Redis connection
        red = get_redis(redis_host, redis_port, redis_password, redis_timeout)
        
        if red then
            -- Try to get cached response
            local cached_data = red:get(cache_key)
            if cached_data and cached_data ~= ngx.null then
                utils.log(ngx.INFO, "Redis cache hit for " .. api_name .. " request")
                
                -- Get cached headers
                local cached_headers_key = cache_key .. ":headers"
                local cached_headers_json = red:get(cached_headers_key)
                local cached_headers = {}
                
                if cached_headers_json and cached_headers_json ~= ngx.null then
                    cached_headers = cjson.decode(cached_headers_json)
                end
                
                -- Get cached status code
                local cached_status_key = cache_key .. ":status"
                local cached_status = red:get(cached_status_key)
                local status_code = 200
                
                if cached_status and cached_status ~= ngx.null then
                    status_code = tonumber(cached_status)
                end
                
                release_redis(red, redis_pool_idle_timeout, redis_pool_size)
                
                -- Record success for circuit breaker (cache hit is a success)
                circuit_breaker.record_success(cb_key)
                
                return cjson.decode(cached_data), status_code, cached_headers
            end
            
            utils.log(ngx.INFO, "Redis cache miss for " .. api_name .. " request")
        end
    end
    
    -- Create HTTP client
    local httpc = http.new()
    
    -- Set timeout
    httpc:set_timeout(config.request_timeout or 10000)
    
    -- Prepare request headers
    local proxied_headers = {}
    
    -- First, add default headers from config
    if config.headers then
        for k, v in pairs(config.headers) do
            proxied_headers[k] = v
        end
    end
    
    -- Then, add headers from the original request if they should be forwarded
    if config.forward_headers then
        if config.forward_headers == true then
            -- Forward all headers except host and connection
            for k, v in pairs(request_headers) do
                if k ~= "host" and k ~= "connection" then
                    proxied_headers[k] = v
                end
            end
        else
            -- Forward only specified headers
            for _, header_name in ipairs(config.forward_headers) do
                if request_headers[header_name] then
                    proxied_headers[header_name] = request_headers[header_name]
                end
            end
        end
    end
    
    -- Get proxy configuration
    local proxy_url = os.getenv("PROXY_URL")
    local use_proxy = config.use_proxy and proxy_url and proxy_url ~= ""
    
    -- Prepare request options
    local request_options = {
        method = request_method or config.method or "GET",
        headers = proxied_headers,
        ssl_verify = config.ssl_verify or false,
        query = query_params
    }
    
    -- Add body if present
    if body and body ~= "" then
        request_options.body = body
    end
    
    -- Add proxy settings if using a proxy
    if use_proxy then
        local proxy_username, proxy_password, proxy_host, proxy_port = parse_proxy_url(proxy_url)
        
        request_options.proxy = {
            uri = "http://" .. proxy_host .. ":" .. proxy_port,
            authorization = "Basic " .. ngx.encode_base64(proxy_username .. ":" .. proxy_password)
        }
    end
    
    -- Construct the full URL
    local full_url = config.target_url
    if api_path and api_path ~= "" then
        -- Remove leading slash if both target_url ends with slash and api_path starts with slash
        if full_url:sub(-1) == "/" and api_path:sub(1, 1) == "/" then
            api_path = api_path:sub(2)
        end
        -- Add slash if neither target_url ends with slash nor api_path starts with slash
        if full_url:sub(-1) ~= "/" and api_path:sub(1, 1) ~= "/" then
            full_url = full_url .. "/"
        end
        full_url = full_url .. api_path
    end
    
    -- Log the request details
    utils.log(ngx.INFO, "Making " .. request_options.method .. " request to " .. full_url)
    
    -- Define the actual request function to be used with retry
    local function make_request()
        local request_start_time = ngx.now()  -- Rename to avoid confusion
        local res, err = httpc:request_uri(full_url, request_options)
        
        -- Handle errors
        if not res then
            utils.log(ngx.ERR, "Request to " .. api_name .. " failed: " .. (err or "unknown error"))
            return nil, 502, err
        end
        
        -- Check status code
        if res.status >= 500 then
            utils.log(ngx.ERR, api_name .. " API returned error status: " .. res.status)
            return nil, res.status, "API returned error status: " .. res.status
        end
        
        -- Parse response if it's JSON
        local response_data
        local content_type = res.headers["content-type"] or ""
        
        if content_type:find("application/json") then
            local parse_err
            response_data, parse_err = utils.parse_json(res.body)
            if not response_data then
                utils.log(ngx.ERR, "Failed to parse " .. api_name .. " response: " .. (parse_err or "unknown error"))
                return nil, 502, "Failed to parse response: " .. (parse_err or "unknown error")
            end
        else
            -- For non-JSON responses, just return the raw body
            response_data = { body = res.body }
        end
        
        return response_data, res.status, nil, res.headers
    end
    
    -- Execute the request with retry logic if configured
    local response_data, status_code, err, response_headers
    
    if config.retry then
        response_data, status_code, err, response_headers = retry_handler.with_retries(make_request, config.retry)
    else
        response_data, status_code, err, response_headers = make_request()
    end
    
    -- Handle the final result
    if not response_data then
        -- Record failure for circuit breaker
        circuit_breaker.record_failure(cb_key)
        if red then release_redis(red, redis_pool_idle_timeout, redis_pool_size) end
        
        -- Record API call statistics (failure)
        api_stats.record_api_call(api_name, status_code, ngx.now() - start_time, err, api_path)
        
        return nil, status_code, nil, err
    end
    
    -- Record success for circuit breaker
    circuit_breaker.record_success(cb_key)
    
    -- Record API call statistics (success)
    api_stats.record_api_call(api_name, status_code, ngx.now() - start_time, nil, api_path)
    
    -- Cache the successful response in Redis if caching is enabled
    if config.enable_cache and red and status_code < 400 then
        -- Cache the response body
        local ok, set_err = red:setex(cache_key, cache_ttl, cjson.encode(response_data))
        if not ok then
            utils.log(ngx.WARN, "Failed to set Redis cache for " .. api_name .. ": " .. (set_err or "unknown error"))
        end
        
        -- Cache the response headers
        local headers_to_cache = {}
        if response_headers then
            for k, v in pairs(response_headers) do
                -- Only cache certain headers
                if k == "content-type" or k == "etag" or k == "cache-control" or k == "last-modified" then
                    headers_to_cache[k] = v
                end
            end
        end
        
        if next(headers_to_cache) then
            red:setex(cache_key .. ":headers", cache_ttl, cjson.encode(headers_to_cache))
        end
        
        -- Cache the status code
        red:setex(cache_key .. ":status", cache_ttl, status_code)
        
        release_redis(red, redis_pool_idle_timeout, redis_pool_size)
    elseif red then
        release_redis(red, redis_pool_idle_timeout, redis_pool_size)
    end
    
    return response_data, status_code, response_headers
end

-- Function to get Redis connection
function get_redis(host, port, password, timeout)
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
function release_redis(red, idle_timeout, pool_size)
    if not red then return end
    
    local ok, err = red:set_keepalive(idle_timeout, pool_size)
    if not ok then
        utils.log(ngx.ERR, "Failed to set Redis keepalive: " .. (err or "unknown error"))
    end
end

-- Function to parse proxy URL
function parse_proxy_url(proxy_url)
    local proxy_username, proxy_password, proxy_host, proxy_port
    
    -- Extract username:password@host:port from the URL
    local auth_host_port = proxy_url:match("http://([^/]+)")
    if auth_host_port then
        local auth, host_port = auth_host_port:match("(.+)@(.+)")
        if auth and host_port then
            proxy_username, proxy_password = auth:match("(.+):(.+)")
            proxy_host, proxy_port = host_port:match("(.+):(.+)")
            proxy_port = tonumber(proxy_port)
        else
            -- No authentication in URL
            proxy_host, proxy_port = auth_host_port:match("(.+):(.+)")
            proxy_port = tonumber(proxy_port)
        end
    end
    
    -- Fallback to defaults if parsing failed
    proxy_host = proxy_host or "p.webshare.io"
    proxy_port = proxy_port or 80
    proxy_username = proxy_username or "xruolauf-US-GB-rotate"
    proxy_password = proxy_password or "1cysf56k28h3"
    
    return proxy_username, proxy_password, proxy_host, proxy_port
end

-- Execute the main function
main() 