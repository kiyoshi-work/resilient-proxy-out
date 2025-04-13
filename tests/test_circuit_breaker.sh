#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Configuration
PROXY_URL="http://localhost:8087/hyperliquid"
FAILURE_THRESHOLD=5  # Should match your circuit breaker configuration
TEST_USER="0x5887de8d37c9c2550a4d0b86127c43b2e1904545"

echo -e "${YELLOW}Circuit Breaker Test Script${NC}"
echo "========================================"
echo "This script will test the circuit breaker functionality by:"
echo "1. Making successful requests to verify normal operation"
echo "2. Forcing failures to trigger the circuit breaker"
echo "3. Verifying the circuit opens after threshold is reached"
echo "4. Waiting for the circuit to transition to half-open"
echo "5. Verifying recovery when the service is available again"
echo "========================================"

# Function to make a request and return status code
make_request() {
    local response=$(curl -s -w "%{http_code}" -o /dev/null \
        -H "Content-Type: application/json" \
        -d "{\"type\":\"frontendOpenOrders\",\"user\":\"$TEST_USER\"}" \
        $PROXY_URL)
    echo $response
}

# Function to make a request and return the full response
make_request_with_response() {
    local response=$(curl -s \
        -H "Content-Type: application/json" \
        -d "{\"type\":\"frontendOpenOrders\",\"user\":\"$TEST_USER\"}" \
        $PROXY_URL)
    echo "$response"
}

# Step 1: Verify normal operation
echo -e "\n${YELLOW}Step 1: Verifying normal operation${NC}"
echo "Making a test request..."
status=$(make_request)

if [ "$status" -eq 200 ]; then
    echo -e "${GREEN}Success! Received 200 status code.${NC}"
else
    echo -e "${RED}Failed! Received $status status code.${NC}"
    echo "Make sure your proxy is running and configured correctly."
    exit 1
fi

# Step 2: Force failures to trigger circuit breaker
echo -e "\n${YELLOW}Step 2: Forcing failures to trigger circuit breaker${NC}"
echo "We'll temporarily modify the target URL in the proxy to cause failures."
echo "Please manually update the target_url in api_proxy.lua to an invalid URL (e.g., https://invalid.example.com)"
echo "Then restart your OpenResty container."

read -p "Press Enter after you've made the change and restarted OpenResty..."

# Step 3: Make requests until circuit opens
echo -e "\n${YELLOW}Step 3: Making requests until circuit opens${NC}"
echo "Making $FAILURE_THRESHOLD+ requests to trigger circuit breaker..."

for i in $(seq 1 $((FAILURE_THRESHOLD + 2))); do
    echo "Request $i..."
    response=$(make_request_with_response)
    echo "Response: $response"
    
    # Check if the response contains circuit breaker message
    if echo "$response" | grep -q "Service temporarily unavailable"; then
        echo -e "${GREEN}Circuit breaker opened successfully after $i requests!${NC}"
        break
    fi
    
    # Small delay between requests
    sleep 1
done

# Step 4: Verify circuit is open
echo -e "\n${YELLOW}Step 4: Verifying circuit is open${NC}"
echo "Making another request to confirm circuit is open..."
response=$(make_request_with_response)
echo "Response: $response"

if echo "$response" | grep -q "Service temporarily unavailable"; then
    echo -e "${GREEN}Confirmed! Circuit is open.${NC}"
else
    echo -e "${RED}Failed! Circuit should be open but request went through.${NC}"
fi

# Step 5: Restore service and wait for recovery
echo -e "\n${YELLOW}Step 5: Restoring service and waiting for recovery${NC}"
echo "Please restore the original target_url in api_proxy.lua and restart OpenResty."
read -p "Press Enter after you've made the change and restarted OpenResty..."

# Step 6: Wait for circuit to transition to half-open
echo -e "\n${YELLOW}Step 6: Waiting for circuit to transition to half-open${NC}"
echo "The circuit should transition to half-open after the reset timeout (default: 30 seconds)."
echo "Waiting for 35 seconds..."
sleep 35

# Step 7: Verify recovery
echo -e "\n${YELLOW}Step 7: Verifying recovery${NC}"
echo "Making requests to verify circuit closes again..."

success_count=0
for i in $(seq 1 5); do
    echo "Request $i..."
    status=$(make_request)
    
    if [ "$status" -eq 200 ]; then
        echo -e "${GREEN}Success! Received 200 status code.${NC}"
        ((success_count++))
    else
        echo -e "${RED}Failed! Received $status status code.${NC}"
    fi
    
    # Small delay between requests
    sleep 2
done

if [ $success_count -gt 0 ]; then
    echo -e "\n${GREEN}Circuit breaker recovery test passed!${NC}"
    echo "The circuit successfully transitioned from open to half-open to closed."
else
    echo -e "\n${RED}Circuit breaker recovery test failed!${NC}"
    echo "The circuit did not recover as expected."
fi

echo -e "\n${YELLOW}Test Summary${NC}"
echo "========================================"
echo "The circuit breaker test is complete."
echo "If all steps passed, your circuit breaker is working correctly."
echo "If any steps failed, review your implementation and configuration."
echo "========================================" 