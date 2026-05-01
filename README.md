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

## Notes

### Tối ưu latency khi đi qua static proxy IPs (keepalive connection pool)

#### Bài toán

Hệ thống dùng 1 list static proxy IPs (rotate qua biến `PROXY_URLS`) để bypass rate limit per-IP của các third-party API. Mỗi request đi:

```
client → openresty → proxy IP → upstream API
```

Vì có thêm 1 hop network qua proxy, latency tăng đáng kể. Phần lớn overhead đến từ:

1. **TCP handshake** với proxy mỗi request (1 RTT).
2. **TLS handshake end-to-end** với upstream (qua `CONNECT` tunnel của HTTP proxy) — tối thiểu 1-2 RTT cho TLS 1.3, 2 RTT cho TLS 1.2.
3. **Proxy authentication** (Basic auth) lặp lại.

Mục tiêu: reuse TCP connection (và TLS tunnel) tới proxy giữa các request → bỏ handshake → giảm latency.

#### Implement cũ — không work

```lua
-- File: docker/openresty/lua/api_proxy.lua (đoạn cũ)
local httpc = http.new()
...
if use_proxy_for_this_request then
    httpc:set_keepalive(1000, 5)  -- ❌ SAI
    ...
    local res, err = httpc:request_uri(full_url, current_request_options)
end
```

Có 2 vấn đề chính:

**1. `set_keepalive` gọi sai chỗ và sai semantics.**

Trong `lua-resty-http`, `set_keepalive(timeout, pool_size)` **không phải config setter**. Nó là method "trả connection hiện tại về pool để reuse" — phải gọi **sau** khi đã đọc xong response body. Trong code cũ, nó được gọi **trước** `request_uri` lúc `httpc` vừa `http.new()` còn chưa connect → fail silently (không có connection nào để pool). Intent (`keepalive timeout 1000ms, pool 5`) bị hiểu nhầm hoàn toàn — không có dòng config nào thực sự áp dụng.

**2. Round-robin strategy giết pool hit rate.**

`request_uri` thực ra **có** auto-pool nội bộ (gọi `set_keepalive` sau khi đọc body xong). Pool key bao gồm `(host, port, proxy_opts, ssl)`. Khi rotate qua N proxy:

- M req/s tổng → mỗi proxy nhận M/N req/s.
- Idle time giữa 2 request cùng pool key (cùng proxy) lớn → connection expire trước khi reuse → pool hit ~ 0.
- Mỗi request gần như đều phải TCP + TLS handshake lại.

Với HTTPS qua HTTP proxy còn tệ hơn: mỗi tunnel `CONNECT` cần TLS handshake end-to-end với upstream, không reuse được = mất 2-3 RTT thừa mỗi request.

#### Fix

```lua
-- File: docker/openresty/lua/api_proxy.lua
local current_request_options = table_clone(request_options)

-- Bật connection pooling ở level request_uri.
-- request_uri tự động trả connection về pool sau khi đọc body,
-- key bởi (host, port, proxy, ssl).
current_request_options.keepalive_timeout = 60000  -- giữ 60s trong pool
current_request_options.keepalive_pool = 50        -- max 50 idle conn / pool key
```

Đồng thời xóa `httpc:set_keepalive(1000, 5)` đặt sai chỗ.

Global pool đã có sẵn trong `nginx.conf`:

```nginx
lua_socket_keepalive_timeout 60s;
lua_socket_pool_size 100;
```

#### Tại sao chỉ fix code chưa đủ — cần đổi proxy strategy

Sau patch, pool work đúng về kỹ thuật. Nhưng nếu giữ nguyên `round_robin` thuần, pool hit rate vẫn thấp do request bị xé đều ra N proxy. Để tối ưu thực sự, có 2 hướng:

1. **Sticky / hash-based proxy selection**: hash theo `api_name` (hoặc client IP) → cùng key → cùng proxy → cùng pool key → reuse cao.
2. **Giảm số proxy active đồng thời**: thay vì rotate hết list, giữ subset nhỏ (2-3 proxy) trừ khi hit rate limit thì mới swap.

Trade-off: sticky làm rate limit per-IP dễ chạm hơn — phù hợp khi backend API rate limit cao hoặc traffic phân bố theo `api_name` không đồng đều.

#### Verify

- Log `res.connection_reused` (nếu `lua-resty-http` version có expose) hoặc bật debug log của resty.http.
- `tcpdump -i any 'tcp[tcpflags] & tcp-syn != 0'` filter theo IP proxy: nếu pool work, số SYN packet phải giảm mạnh so với số request.
- So sánh `p50`/`p95` latency trước/sau patch qua `benchmark.sh`.

#### Tunables

| Param | Giá trị | Ý nghĩa |
|-------|---------|---------|
| `keepalive_timeout` | 60000 ms | Connection idle trong pool 60s trước khi đóng |
| `keepalive_pool` | 50 | Max idle conn per `(host, port, proxy)` key |
| `lua_socket_pool_size` | 100 | Global cap per worker (nginx.conf) |
| `lua_socket_keepalive_timeout` | 60s | Global default (nginx.conf) |

Tăng `keepalive_pool` nếu concurrent request per proxy cao. Tăng `keepalive_timeout` nếu traffic burst với khoảng cách lớn — nhưng để ý proxy/firewall có thể đóng idle connection ở phía họ.

## Contributing

Contributions are welcome! Please feel free to submit a PR.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

