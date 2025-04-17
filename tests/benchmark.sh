#!/bin/bash

RUNS=2
TOTAL_TIME=0

echo "Start benchmark $RUNS times..."

for (( i=1; i<=$RUNS; i++ ))
do
  echo "Run $i times..."
  
  # Measure execution time of curl command
  START_TIME=$(date +%s.%N)
  
  # Save response to variable instead of redirecting to /dev/null
  RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -d '{"type":"clearinghouseState", "user": "0xf6779a38203d47718139d3254237c43201493f00"}' \
    "http://localhost:8087/api/hyperliquid/info")
  
  END_TIME=$(date +%s.%N)

  # Calculate execution time (seconds)
  EXECUTION_TIME=$(echo "$END_TIME - $START_TIME" | bc)
  
  echo "Time: $EXECUTION_TIME seconds"
  
  # Log response
  echo "Response: $RESPONSE"
  
  # Add to total time
  TOTAL_TIME=$(echo "$TOTAL_TIME + $EXECUTION_TIME" | bc)

done

# Calculate average time
AVERAGE_TIME=$(echo "scale=4; $TOTAL_TIME / $RUNS" | bc)

echo "----------------------------------------"
echo "Benchmark result:"
echo "Total runs: $RUNS"
echo "Total time: $TOTAL_TIME seconds"
echo "Average time: $AVERAGE_TIME seconds"
