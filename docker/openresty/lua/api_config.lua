local _M = {}

-- API configurations
local api_configs = {
    ip = {
        target_url = "https://ipinfo.io",
        method = "GET",
        requires_body = false,
        enable_cache = false,
        cache_ttl = 60,  -- 60 seconds
        cache_header_strategy = "none",  -- Use "all" to include all headers in cache key
        use_proxy = true,
        proxy_strategy = "round_robin", -- can be "round_robin", "on_rate_limit", or "never"
        headers = {
            ["Content-Type"] = "application/json",
            ["Accept"] = "application/json"
        },
        forward_headers = false,  -- Don't forward client headers
        circuit_breaker = {
            failure_threshold = 5,
            reset_timeout = 30,
            request_timeout = 10000,
            success_threshold = 2
        },
        retry = {
            max_attempts = 3,
            initial_delay = 1,
            max_delay = 10,
            backoff_factor = 2,
            retry_on_status = {500, 502, 503, 504, 429},
            retry_on_errors = {"timeout", "connection refused", "connection reset", "socket", "host not found"}
        }
    },
    -- Hyperliquid API configuration
    hyperliquid = {
        target_url = "https://api.hyperliquid.xyz",
        method = "POST",
        requires_body = true,
        enable_cache = false,
        cache_ttl = 60,  -- 60 seconds
        cache_header_strategy = "none",  -- Use "all" to include all headers in cache key
        use_proxy = true,
        -- Hyperliquid rate limit: 600 req/min per IP = 10 rps per IP.
        -- Subset(3) concentrates traffic onto 3 proxies for warm keepalive
        -- pools while giving 30 rps aggregate headroom (3 * 10 rps). On 429
        -- we slide the window to the next 3 proxies, evicting the rate-limited
        -- one. Increase proxy_subset_size if peak load > 30 rps; decrease for
        -- maximum pool reuse if peak load is well under 10 rps.
        proxy_strategy = "subset", -- "round_robin" | "sticky" | "subset" | "on_rate_limit" | "never"
        proxy_subset_size = 3,
        headers = {
            ["Content-Type"] = "application/json",
            ["Accept"] = "application/json"
        },
        forward_headers = false,  -- Don't forward client headers
        circuit_breaker = {
            failure_threshold = 5,
            reset_timeout = 30,
            request_timeout = 10000,
            success_threshold = 2
        },
        retry = {
            max_attempts = 3,
            initial_delay = 1,
            max_delay = 10,
            backoff_factor = 2,
            retry_on_status = {500, 502, 503, 504, 429},
            retry_on_errors = {"timeout", "connection refused", "connection reset", "socket", "host not found"}
        }
    },
    
    -- Birdeye API configuration
    birdeye = {
        target_url = "https://public-api.birdeye.so",
        method = "POST",  -- Default method, will be overridden by client request
        requires_body = false,  -- Some endpoints might not require a body
        enable_cache = true,
        cache_ttl = 60,  -- 60 seconds
        use_proxy = true,
        headers = {
            ["Content-Type"] = "application/json",
            ["Accept"] = "application/json"
        },
        forward_headers = {"X-API-KEY", "x-chain"},  -- Forward these specific headers
        cache_header_strategy = "none",  -- Use "all" to include all headers in cache key
        cache_headers = {"X-API-KEY", "x-chain"},  -- Include these headers in cache key
        circuit_breaker = {
            failure_threshold = 5,
            reset_timeout = 30,
            request_timeout = 10000,
            success_threshold = 2
        },
        retry = {
            max_attempts = 3,
            initial_delay = 0.5,
            max_delay = 5,
            backoff_factor = 2,
            retry_on_status = {500, 502, 503, 504, 429},
            retry_on_errors = {"timeout", "connection refused", "connection reset", "socket", "host not found"}
        }
    },
    
    -- Example of another API configuration
    coinbase = {
        target_url = "https://api.coinbase.com/v2",
        method = "GET",
        requires_body = false,
        enable_cache = true,
        cache_ttl = 120,  -- 2 minutes
        use_proxy = false,
        headers = {
            ["Accept"] = "application/json"
        },
        forward_headers = true,  -- Forward all client headers
        cache_header_strategy = "none",  -- Use "all" to include all headers in cache key
        circuit_breaker = {
            failure_threshold = 3,
            reset_timeout = 60,
            request_timeout = 5000,
            success_threshold = 2
        },
        retry = {
            max_attempts = 2,
            initial_delay = 1,
            max_delay = 3,
            backoff_factor = 1.5,
            retry_on_status = {500, 502, 503, 504},
            retry_on_errors = {"timeout", "connection refused"}
        }
    },
    
    -- Add more API configurations as needed
}

-- Function to get API configuration
function _M.get_config(api_name)
    return api_configs[api_name]
end

-- Function to add or update API configuration
function _M.set_config(api_name, config)
    api_configs[api_name] = config
end

return _M 