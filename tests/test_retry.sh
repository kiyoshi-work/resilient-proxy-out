#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Configuration
PROXY_URL="http://localhost:8087/api/hyperliquid"
TEST_USER="0x5887de8d37c9c2550a4d0b86127c43b2e1904545"

echo -e "${YELLOW}Retry Mechanism Test Script${NC}"
echo "========================================"
echo "This script will test the retry mechanism by:"
echo "1. Making a request to a temporarily unavailable endpoint"
echo "2. Observing retry attempts with exponential backoff"
echo "3. Verifying successful recovery when the service becomes available"
echo "========================================"

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
response=$(make_request_with_response)
echo "Raw response: $response"

# Kiểm tra response có phải là JSON hợp lệ không
if echo "$response" | jq . > /dev/null 2>&1; then
    echo -e "${GREEN}Received valid JSON response.${NC}"
    
    # Kiểm tra nếu response có trường orders hoặc body (tùy thuộc vào cấu trúc API)
    if echo "$response" | jq -e '.orders' > /dev/null 2>&1 || echo "$response" | jq -e '.body' > /dev/null 2>&1; then
        echo -e "${GREEN}Success! Response contains expected data.${NC}"
    else
        echo -e "${YELLOW}Warning: Response is valid JSON but doesn't contain expected fields.${NC}"
        echo "This might be normal depending on your API structure."
    fi
else
    echo -e "${RED}Failed! Received invalid JSON response: $response${NC}"
    echo "Make sure your proxy is running and configured correctly."
    exit 1
fi

# Step 2: Force temporary failure to trigger retries
echo -e "\n${YELLOW}Step 2: Forcing temporary failure to trigger retries${NC}"
echo "We'll temporarily modify the target URL in the proxy to cause failures."
echo "Please manually update the target_url in api_config.lua to an invalid URL (e.g., https://invalid.example.com)"
echo "Then restart your OpenResty container."

read -p "Press Enter after you've made the change and restarted OpenResty..."

# Step 3: Make request and observe retry behavior
echo -e "\n${YELLOW}Step 3: Making request and observing retry behavior${NC}"
echo "Making request to trigger retry mechanism..."
echo "Check the OpenResty logs to observe the retry attempts with increasing delays."

response=$(make_request_with_response)
echo "Response: $response"

# Step 4: Restore service
echo -e "\n${YELLOW}Step 4: Restoring service${NC}"
echo "Please restore the original target_url in api_config.lua and restart OpenResty."
read -p "Press Enter after you've made the change and restarted OpenResty..."

# Step 5: Verify recovery
echo -e "\n${YELLOW}Step 5: Verifying recovery${NC}"
echo "Making request to verify service is working again..."
response=$(make_request_with_response)
echo "Raw response: $response"

# Kiểm tra response có phải là JSON hợp lệ không
if echo "$response" | jq . > /dev/null 2>&1; then
    echo -e "${GREEN}Received valid JSON response after recovery.${NC}"
    
    # Kiểm tra nếu response có trường orders hoặc body
    if echo "$response" | jq -e '.orders' > /dev/null 2>&1 || echo "$response" | jq -e '.body' > /dev/null 2>&1; then
        echo -e "${GREEN}Success! Service recovered successfully.${NC}"
    else
        echo -e "${YELLOW}Warning: Response is valid JSON but doesn't contain expected fields.${NC}"
        echo "This might be normal depending on your API structure."
    fi
else
    echo -e "${RED}Failed! Service did not recover properly: $response${NC}"
fi

echo -e "\n${YELLOW}Test Summary${NC}"
echo "========================================"
echo "The retry mechanism test is complete."
echo "If all steps passed, your retry mechanism is working correctly."
echo "If any steps failed, review your implementation and configuration."
echo "========================================" 