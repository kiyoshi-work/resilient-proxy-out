# Resilient Proxy

A resilient proxy built with OpenResty and Redis, designed to provide caching, rate limiting, and proxying capabilities for third party APIs.

## Overview
- Request caching to reduce API load
- Automatic failover to direct IP addresses when DNS fails
- Optional proxy support for rate limit management
- High performance through OpenResty/Nginx

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

docker/
├── openresty/
│   ├── conf.d/proxy.conf    # Nginx proxy config
│   ├── lua/
│   │   ├── proxy.lua        # Main proxy logic
│   │   └── utils.lua        # Utility functions
│   ├── Dockerfile
│   └── nginx.conf


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

