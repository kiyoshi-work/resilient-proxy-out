#!/bin/bash

# Số lần chạy benchmark
RUNS=3
TOTAL_TIME=0
SUCCESSFUL_RUNS=0

echo "Bắt đầu benchmark với $RUNS lần chạy..."

# Tạo file cookie để lưu session
COOKIE_JAR="cookie_jar.txt"
touch $COOKIE_JAR

# Proxy configuration
PROXY="http://xruolauf-US-GB-rotate:1cysf56k28h3@p.webshare.io:80"

# Format cho curl write-out
FORMAT='{
  "time_namelookup": %{time_namelookup},
  "time_connect": %{time_connect},
  "time_appconnect": %{time_appconnect},
  "time_pretransfer": %{time_pretransfer},
  "time_redirect": %{time_redirect},
  "time_starttransfer": %{time_starttransfer},
  "time_total": %{time_total}
}'

# Tạo file tạm thời để lưu format
FORMAT_FILE=$(mktemp)
echo "$FORMAT" > "$FORMAT_FILE"

# Thực hiện request đầu tiên để thiết lập kết nối
echo "Preloading proxy handshake..."
curl -s -o /dev/null -c $COOKIE_JAR \
  -X HEAD "https://api.hyperliquid.xyz" \
  -H "Connection: keep-alive" \
  -x "$PROXY" \
  -w "@$FORMAT_FILE" 2>/dev/null | jq . || echo "Preload failed"

# Hàm phân tích thời gian
analyze_timing() {
  local timing_data="$1"
  
  # Trích xuất các giá trị thời gian
  local time_namelookup=$(echo "$timing_data" | jq -r '.time_namelookup')
  local time_connect=$(echo "$timing_data" | jq -r '.time_connect')
  local time_appconnect=$(echo "$timing_data" | jq -r '.time_appconnect')
  local time_pretransfer=$(echo "$timing_data" | jq -r '.time_pretransfer')
  local time_starttransfer=$(echo "$timing_data" | jq -r '.time_starttransfer')
  local time_total=$(echo "$timing_data" | jq -r '.time_total')
  
  # Tính toán thời gian cho từng giai đoạn
  local dns_lookup=$(echo "$time_namelookup" | awk '{printf "%.6f", $1}')
  local tcp_connection=$(echo "$time_connect - $time_namelookup" | bc | awk '{printf "%.6f", $1}')
  local ssl_handshake=$(echo "$time_appconnect - $time_connect" | bc | awk '{printf "%.6f", $1}')
  local server_processing=$(echo "$time_starttransfer - $time_pretransfer" | bc | awk '{printf "%.6f", $1}')
  local content_transfer=$(echo "$time_total - $time_starttransfer" | bc | awk '{printf "%.6f", $1}')
  
  echo "Chi tiết thời gian:"
  echo "  DNS Lookup:       ${dns_lookup}s"
  echo "  TCP Connection:   ${tcp_connection}s"
  echo "  SSL Handshake:    ${ssl_handshake}s"
  echo "  Server Processing: ${server_processing}s"
  echo "  Content Transfer:  ${content_transfer}s"
  echo "  Total:            ${time_total}s"
}

# Hàm thực hiện benchmark
run_benchmark() {
  run_number=$1
  echo "Chạy lần thứ $run_number..."
  
  # Tạo file tạm thời để lưu response body
  RESPONSE_BODY=$(mktemp)
  
  # Thực hiện request và lưu thông tin timing
  timing_data=$(curl -s -X POST "https://api.hyperliquid.xyz/info" \
    -H "Content-Type: application/json" \
    -H "Connection: keep-alive" \
    -b $COOKIE_JAR -c $COOKIE_JAR \
    -x "$PROXY" \
    --keepalive-time 60 \
    -d '{
      "type": "clearinghouseState",
      "user": "0xf6779a38203d47718139d3254237c43201493f00"
    }' \
    -o "$RESPONSE_BODY" \
    -w "@$FORMAT_FILE" 2>/dev/null)
  
  if [ $? -eq 0 ]; then
    # Lấy thời gian tổng
    time_total=$(echo "$timing_data" | jq -r '.time_total')
    
    echo "----------------------------------------"
    echo "Lần chạy $run_number hoàn thành"
    analyze_timing "$timing_data"
    # echo "Nội dung response:"
    # cat "$RESPONSE_BODY" | jq . || cat "$RESPONSE_BODY"
    echo "----------------------------------------"
    
    TOTAL_TIME=$(echo "$TOTAL_TIME + $time_total" | bc)
    SUCCESSFUL_RUNS=$((SUCCESSFUL_RUNS + 1))
    
    # Xóa file tạm thời
    rm "$RESPONSE_BODY"
    return 0
  else
    echo "Lỗi trong lần chạy $run_number"
    rm "$RESPONSE_BODY"
    return 1
  fi
}

# Chạy benchmark
for i in $(seq 1 $RUNS); do
  run_benchmark $i
  # Thêm một khoảng nghỉ nhỏ giữa các request để giữ kết nối
  sleep 0.5
done

# Tính kết quả
if [ $SUCCESSFUL_RUNS -gt 0 ]; then
  avg_time=$(echo "scale=4; $TOTAL_TIME / $SUCCESSFUL_RUNS" | bc)
else
  avg_time=0
fi

echo "Kết quả benchmark:"
echo "Tổng số lần chạy thành công: $SUCCESSFUL_RUNS/$RUNS"
echo "Thời gian trung bình: ${avg_time}s"

# Xóa file cookie và file format tạm thời
rm $COOKIE_JAR
rm "$FORMAT_FILE"