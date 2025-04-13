curl 'http://localhost:8087/hyperliquid/info' \
  -H 'Accept: */*' \
  -H 'Accept-Language: en-US,en;q=0.9,vi;q=0.8' \
  -H 'Connection: keep-alive' \
  -H 'Content-Type: application/json' \
  --data-raw '{"type":"frontendOpenOrders","user":"0x5887de8d37c9c2550a4d0b86127c43b2e1904545"}'

# curl 'https://api.hyperliquid.xyz/api/hyperliquid/info' \
#   circurbreaker, redis cache, Prefetch worker, prevent Rate Limiter (use proxy with retry mechanism)