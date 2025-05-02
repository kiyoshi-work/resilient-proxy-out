# Resilient Proxy Out

A resilient proxy built with OpenResty (a powerful web platform that extends NGINX with Lua scripting capabilities), designed to provide caching, rate limiting, and proxying capabilities for third party APIs.

## Features

- **Circuit Breaker Pattern**: Automatically detects failing services and prevents cascading failures, the circuit breaker can be configured per API with the following options:
    - `failure_threshold`: Number of failures before circuit is tripped (default: 5)
    - `reset_timeout`: Time in seconds before circuit is reset (default: 30)
    - `request_timeout`: Request timeout in milliseconds (default: 10000)
    - `success_threshold`: Number of successful requests before circuit is reset (default: 2)
- **Request Caching**: Reduces load on backend services by caching responses in Redis, the cache can be configured per API with the following options:
    - `enable_cache`: Enable caching (default: false)
    - `cache_ttl`: Cache time-to-live in seconds (default: 60)
    - `cache_header_strategy`: Strategy to use for caching headers (default: "none")
    - `cache_headers`: Headers to use for caching (default: "none")
- **Proxy Support**: Optional proxy configuration for handling rate-limited APIs, the proxy can be configured per API with the following options:
    - `use_proxy`: Enable proxy (default: false)
    - `proxy_strategy`: can be "round_robin", "on_rate_limit", or "never" (default: "round_robin")
- **Retry Mechanism**: Automatically retries failed requests with exponential backoff , the retry mechanism can be configured per API with the following options:

    - `max_attempts`: Maximum number of retry attempts (default: 3)
    - `initial_delay`: Initial delay in seconds before first retry (default: 1)
    - `max_delay`: Maximum delay in seconds between retries (default: 10)
    - `backoff_factor`: Exponential backoff multiplier (default: 2)
    - `retry_on_status`: HTTP status codes that trigger a retry (default: 500, 502, 503, 504, 429)
    - `retry_on_errors`: Connection errors that trigger a retry (default: timeout, connection refused, etc.)
- **Detailed API Statistics**: Comprehensive statistics tracking for all API calls with a visual dashboard:
    - **Path-Level Statistics**: Track and analyze API usage at both the API and individual path levels
    - **Response Time Metrics**: Monitor min, median, 95th percentile, and max response times
    - **Status Code Distribution**: Visualize the distribution of HTTP status codes
    - **Error Tracking**: Log and display recent error messages for troubleshooting
    - **Time-Based Analysis**: View statistics for all time, daily, or hourly periods
    - **Auto-Refresh**: Configure automatic dashboard updates at customizable intervals

- **Dashboards & Monitoring**: The proxy includes several built-in dashboards for monitoring and troubleshooting:
  - **Statistics Dashboard**: `/stats-dashboard` - path-level statistics, response time metrics, status code distribution, error tracking, time-based analysis (all/daily/hourly), and auto-refresh capabilities
  - **Circuit Breaker Dashboard**: `/cb-dashboard` - Real-time circuit status (closed/open/half-open), failure counts, configuration details, and reset timers


## Getting Started

### Prerequisites

- Docker and Docker Compose
- Git

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/kiyoshitaro/resilient-proxy-out.git
   cd resilient-proxy-out
   ```

2. Configure your environment:
   ```bash
   cp .env.sample .env
   ```
   
3. Edit the `.env` file to set your configuration:
   ```
   PROXY_URL=https://your-proxy-url.com
   REDIS_HOST=redis
   REDIS_PORT=6378
   ```

4. Start the services:
   ```bash
   docker compose up --build -d --remove-orphans
   ```

5. Verify the installation:
   ```bash
   curl http://localhost:8087/health
   ```

### Project Structure
```bash
docker/
├── openresty/
│   ├── conf.d/proxy.conf    # Nginx proxy config
│   ├── html/*.html    # Circuit Breaker Dashboard
│   ├── lua/
│   │   ├── api_config.lua        # API configuration
│   │   ├── api_proxy.lua        # Main proxy logic
│   │   └── utils.lua        # Utility functions
│   ├── Dockerfile
│   └── nginx.conf
├── tests/
│   └── test_*.sh    # Test script for circuit breaker
├── README.md
└── .env.sample
```

## Usage
### Making API Requests
Send requests to the gateway on port 8087:

```bash
curl 'http://localhost:8087/api/hyperliquid/info' \
  -H 'Content-Type: application/json' \
  --data-raw '{"type":"frontendOpenOrders","user":"0x5887de8d37c9c2550a4d0b86127c43b2e1904545"'
```
### Health Checks
```bash
curl http://localhost:8087/health
```

## Contributing

Contributions are welcome! Please feel free to submit a PR.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

