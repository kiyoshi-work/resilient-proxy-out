local http = require "resty.http"
local cjson = require "cjson"
local utils = require "utils"

-- Configuration
local target_url = "https://api.hyperliquid.xyz/info"

-- Get proxy URL from nginx variable (defined in nginx.conf)
local proxy_url = ngx.var.proxy_url
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

-- Cache configuration
local cache = ngx.shared.api_cache
local cache_ttl = 60  -- Cache TTL in seconds

-- Function to make the proxied request
local function make_proxied_request(body)
    -- Check cache first
    local cache_key = ngx.md5(body)
    local cached_response = cache:get(cache_key)
    
    if cached_response then
        utils.log(ngx.INFO, "Cache hit for request")
        return cjson.decode(cached_response)
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
        return nil, "Failed to make request: " .. (err or "unknown error")
    end
    
    -- Check status code
    if res.status < 200 or res.status >= 300 then
        utils.log(ngx.ERR, "API returned error status: " .. res.status)
        return nil, "API returned error status: " .. res.status
    end
    
    -- Parse response
    local response_data, parse_err = utils.parse_json(res.body)
    if not response_data then
        utils.log(ngx.ERR, "Failed to parse response: " .. (parse_err or "unknown error"))
        return nil, "Failed to parse response: " .. (parse_err or "unknown error")
    end
    
    -- Cache the successful response
    cache:set(cache_key, res.body, cache_ttl)
    
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
