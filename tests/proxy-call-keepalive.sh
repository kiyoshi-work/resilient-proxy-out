#!/bin/bash

RUNS=20
TOTAL_TIME=0

# Create file for cookie jar and connection cache
COOKIE_JAR=$(mktemp)
CONN_CACHE=$(mktemp)


echo "Start benchmark $RUNS times..."

AVG_TIMES_DNS=0
AVG_TIMES_CONNECT=0
AVG_TIMES_PRETRANSFER=0
AVG_TIMES_APPCONNECT=0
AVG_TIMES_STARTTRANSFER=0
AVG_TIMES_TOTAL=0

# Initialize connection to proxy before starting benchmark
echo "Initialize connection to proxy..."
INIT_RESPONSE=$(curl -s -w \
"\n---CURL_TIMING_INFO---\n\
DNS lookup: %{time_namelookup}s\n\
TCP connection: %{time_connect}s\n\
Proxy handshake: %{time_pretransfer}s\n\
TLS handshake: %{time_appconnect}s\n\
Start transfer: %{time_starttransfer}s\n\
Total time: %{time_total}s" \
  -c "$COOKIE_JAR" \
  -H "Connection: keep-alive" \
  --connect-timeout 5 \
  --connect-to ::p.webshare.io:80 \
  -x "http://xruolauf-US-GB-rotate:1cysf56k28h3@p.webshare.io:80/" \
  "https://ipinfo.io")

echo "Initialize connection result:"
echo "$INIT_RESPONSE"

# Wait a moment to ensure the connection is established
sleep 1

for (( i=1; i<=$RUNS; i++ ))
do
  echo "Run $i times..."
  
  # Get response and timing details, using keep-alive and connection cache
  RESULT=$(curl -s -w "\n---CURL_TIMING_INFO---\nDNS lookup: %{time_namelookup}s\nTCP connection: %{time_connect}s\nProxy handshake: %{time_pretransfer}s\nTLS handshake: %{time_appconnect}s\nStart transfer: %{time_starttransfer}s\nTotal time: %{time_total}s" \
    -X GET \
    -H "Content-Type: application/json" \
    -H "Connection: keep-alive" \
    -b "$COOKIE_JAR" \
    -c "$COOKIE_JAR" \
    --connect-to ::p.webshare.io:80 \
    --keepalive-time 60 \
    -x "http://xruolauf-US-GB-rotate:1cysf56k28h3@p.webshare.io:80/" \
    "https://ipinfo.io")
  
  # Split response and timing details by clear marker
  RESPONSE=$(echo "$RESULT" | sed -n '1,/---CURL_TIMING_INFO---/p' | sed '$d')
  TIMING_INFO=$(echo "$RESULT" | sed -n '/---CURL_TIMING_INFO---/,$p' | sed '1d')
  
  echo "Timing info:"
  echo "$TIMING_INFO"
  
  # Extract time values
  DNS_TIME=$(echo "$TIMING_INFO" | grep "DNS lookup" | awk '{print $3}' | sed 's/s//')
  CONNECT_TIME=$(echo "$TIMING_INFO" | grep "TCP connection" | awk '{print $3}' | sed 's/s//')
  PRETRANSFER_TIME=$(echo "$TIMING_INFO" | grep "Proxy handshake" | awk '{print $3}' | sed 's/s//')
  APPCONNECT_TIME=$(echo "$TIMING_INFO" | grep "TLS handshake" | awk '{print $3}' | sed 's/s//')
  STARTTRANSFER_TIME=$(echo "$TIMING_INFO" | grep "Start transfer" | awk '{print $3}' | sed 's/s//')
  TOTAL_TIME=$(echo "$TIMING_INFO" | grep "Total time" | awk '{print $3}' | sed 's/s//')
  
  # Add to average time
  AVG_TIMES_DNS=$(echo "${AVG_TIMES_DNS} + $DNS_TIME" | bc)
  AVG_TIMES_CONNECT=$(echo "${AVG_TIMES_CONNECT} + $CONNECT_TIME" | bc)
  AVG_TIMES_PRETRANSFER=$(echo "${AVG_TIMES_PRETRANSFER} + $PRETRANSFER_TIME" | bc)
  AVG_TIMES_APPCONNECT=$(echo "${AVG_TIMES_APPCONNECT} + $APPCONNECT_TIME" | bc)
  AVG_TIMES_STARTTRANSFER=$(echo "${AVG_TIMES_STARTTRANSFER} + $STARTTRANSFER_TIME" | bc)
  AVG_TIMES_TOTAL=$(echo "${AVG_TIMES_TOTAL} + $TOTAL_TIME" | bc)
  
  # Display response content
  echo "Response content:"
  if [ -z "$RESPONSE" ]; then
    echo "WARNING: Response is empty!"
    # Try to display the entire result for debugging
    echo "Raw result:"
    echo "$RESULT"
  else
    echo "$RESPONSE"
  fi
  echo "----------------------------------------"
done

echo "Logging DNS time: ${AVG_TIMES_DNS}, ${AVG_TIMES_CONNECT}, ${AVG_TIMES_PRETRANSFER}, ${AVG_TIMES_APPCONNECT}, ${AVG_TIMES_STARTTRANSFER}, ${AVG_TIMES_TOTAL}"

# Calculate average time for each stage
echo "Benchmark result:"
echo "Total runs: $RUNS"
echo "Average time:"
echo "DNS lookup: $(echo "scale=4; ${AVG_TIMES_DNS} / $RUNS" | bc)s"
echo "TCP connection: $(echo "scale=4; ${AVG_TIMES_CONNECT} / $RUNS" | bc)s"
echo "Proxy handshake: $(echo "scale=4; ${AVG_TIMES_PRETRANSFER} / $RUNS" | bc)s"
echo "TLS handshake: $(echo "scale=4; ${AVG_TIMES_APPCONNECT} / $RUNS" | bc)s"
echo "Start transfer: $(echo "scale=4; ${AVG_TIMES_STARTTRANSFER} / $RUNS" | bc)s"
echo "Total time: $(echo "scale=4; ${AVG_TIMES_TOTAL} / $RUNS" | bc)s"

# Clean up
rm -f $COOKIE_JAR $CONN_CACHE





# curl -s -o /dev/null -w \
# "DNS lookup          : %{time_namelookup}s\n\
# TCP connection       : %{time_connect}s\n\
# Proxy handshake      : %{time_pretransfer}s\n\
# TLS handshake        : %{time_appconnect}s\n\
# Start transfer       : %{time_starttransfer}s\n\
# Total time           : %{time_total}s\n" \
# -X POST \
# -H "Content-Type: application/json" \
# -x "http://xruolauf-US-GB-rotate:1cysf56k28h3@p.webshare.io:80/" \
# -d '{"type":"clearinghouseState", "user": "0xf6779a38203d47718139d3254237c43201493f00"}' \
# "https://api.hyperliquid.xyz/info"

