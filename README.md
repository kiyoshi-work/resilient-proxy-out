# Resilient Proxy

A resilient proxy built with OpenResty and Redis, designed to provide caching, rate limiting, and proxying capabilities for third party APIs.

## Features

- **Circuit Breaker Pattern**: Automatically detects failing services and prevents cascading failures
- **Request Caching**: Reduces load on backend services by caching responses in Redis
- **Proxy Support**: Optional proxy configuration for handling rate-limited APIs

## Getting Started

### Prerequisites

- Docker and Docker Compose
- Git

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/kiyoshitaro/resilient-proxy.git
   cd resilient-proxy
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
curl 'http://localhost:8080/hyperliquid' \
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

