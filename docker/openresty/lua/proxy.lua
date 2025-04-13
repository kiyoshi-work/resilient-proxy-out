local http = require "resty.http"
local cjson = require "cjson"
local utils = require "utils"
local redis = require "resty.redis"  -- Add Redis library

-- Configuration
local target_url = "https://api.hyperliquid.xyz/info"

-- Get proxy URL from nginx variable (defined in nginx.conf)
-- local proxy_url = ngx.var.proxy_url

local proxy_url = os.getenv("PROXY_URL")
local use_proxy = proxy_url and proxy_url ~= ""

if use_proxy then
    ngx.log(ngx.INFO, "Proxy URL: " .. proxy_url)
else
    ngx.log(ngx.INFO, "No proxy URL provided, making direct request")
end

-- Parse proxy URL components
local proxy_username, proxy_password, proxy_host, proxy_port

-- Only parse proxy components if we're using a proxy
if use_proxy then
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
end

-- Redis configuration from nginx variables
-- local redis_host = ngx.var.redis_host or "redis"
local redis_host = os.getenv("REDIS_HOST")
local redis_port = tonumber(os.getenv("REDIS_PORT") or 6379)
local redis_password = os.getenv("REDIS_PASSWORD") or nil
local redis_timeout = tonumber(os.getenv("REDIS_TIMEOUT") or 1000)  -- 1 second
local redis_pool_size = tonumber(os.getenv("REDIS_POOL_SIZE") or 100)
local redis_pool_idle_timeout = tonumber(os.getenv("REDIS_POOL_IDLE_TIMEOUT") or 10000)  -- 10 seconds
local cache_ttl = tonumber(os.getenv("CACHE_TTL") or 60)  -- Cache TTL in seconds

-- Function to get Redis connection
local function get_redis()
    local red = redis:new()
    red:set_timeout(redis_timeout)
    local ok, err = red:connect(redis_host, redis_port)
    if not ok then
        utils.log(ngx.ERR, "Failed to connect to Redis: " .. (err or "unknown error"))
        return nil, err
    end
    
    -- Authenticate if password is provided
    if redis_password then
        local auth_ok, auth_err = red:auth(redis_password)
        if not auth_ok then
            utils.log(ngx.ERR, "Failed to authenticate with Redis: " .. (auth_err or "unknown error"))
            return nil, auth_err
        end
    end
    utils.log(ngx.INFO, "Redis connected successfully to " .. redis_host .. ":" .. redis_port)
    return red
end

-- Function to release Redis connection back to the connection pool
local function release_redis(red)
    if not red then return end
    
    local ok, err = red:set_keepalive(redis_pool_idle_timeout, redis_pool_size)
    if not ok then
        utils.log(ngx.ERR, "Failed to set Redis keepalive: " .. (err or "unknown error"))
    end
end

-- Function to make the proxied request
local function make_proxied_request(body)
    -- Check Redis cache first
    local cache_key = "api_cache:" .. ngx.md5(body)
    
    -- Get Redis connection
    local red, conn_err = get_redis()
    if not red then
        utils.log(ngx.WARN, "Proceeding without cache due to Redis connection error: " .. (conn_err or "unknown error"))
    else
        -- Try to get cached response
        local cached_response, cache_err = red:get(cache_key)
        if cached_response and cached_response ~= ngx.null then
            utils.log(ngx.INFO, "Redis cache hit for request")
            release_redis(red)
            return cjson.decode(cached_response)
        end
        
        if cache_err then
            utils.log(ngx.WARN, "Redis cache get error: " .. cache_err)
        else
            utils.log(ngx.INFO, "Redis cache miss for request")
        end
    end
    
    -- Create HTTP client
    local httpc = http.new()
    
    -- Set timeout
    httpc:set_timeout(10000)  -- 10 seconds
    
    -- Prepare request
    local request_headers = {
        ["Content-Type"] = "application/json",
        ["Accept"] = "application/json"
    }
    
    -- Prepare request options
    local request_options = {
        method = "POST",
        body = body,
        headers = request_headers,
        ssl_verify = false,  -- You might want to set this to true in production
    }
    
    -- Add proxy settings only if we're using a proxy
    if use_proxy then
        request_options.proxy = {
            uri = "http://" .. proxy_host .. ":" .. proxy_port,
            authorization = "Basic " .. ngx.encode_base64(proxy_username .. ":" .. proxy_password)
        }
    end
    
    -- Make the request
    local res, err = httpc:request_uri(target_url, request_options)
    
    -- Handle errors
    if not res then
        utils.log(ngx.ERR, "Request failed: " .. (err or "unknown error"))
        if red then release_redis(red) end
        return nil, "Failed to make request: " .. (err or "unknown error")
    end
    
    -- Check status code
    if res.status < 200 or res.status >= 300 then
        utils.log(ngx.ERR, "API returned error status: " .. res.status)
        if red then release_redis(red) end
        return nil, "API returned error status: " .. res.status
    end
    
    -- Parse response
    local response_data, parse_err = utils.parse_json(res.body)
    if not response_data then
        utils.log(ngx.ERR, "Failed to parse response: " .. (parse_err or "unknown error"))
        if red then release_redis(red) end
        return nil, "Failed to parse response: " .. (parse_err or "unknown error")
    end
    
    -- Cache the successful response in Redis
    if red then
        local ok, set_err = red:setex(cache_key, cache_ttl, res.body)
        if not ok then
            utils.log(ngx.WARN, "Failed to set Redis cache: " .. (set_err or "unknown error"))
        end
        release_redis(red)
    end
    
    return response_data
end

-- Main function
local function main()
    -- Get request body
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    
    -- Validate request
    if not body or body == "" then
        utils.json_response({
            error = "Request body is required"
        }, 400)
        return
    end
    
    -- Validate JSON
    local request_data, err = utils.parse_json(body)
    if not request_data then
        utils.json_response({
            error = "Invalid JSON in request body: " .. (err or "unknown error")
        }, 400)
        return
    end
    
    -- Make the proxied request
    local response_data, request_err = make_proxied_request(body)
    
    -- Handle errors
    if not response_data then
        utils.json_response({
            error = request_err or "Unknown error occurred"
        }, 500)
        return
    end
    
    -- Return the response
    utils.json_response(response_data)
end

-- Execute the main function
main()
