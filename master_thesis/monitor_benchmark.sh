#!/bin/bash
# Monitor the running benchmark

LOG_FILE="benchmark_full.log"

echo "==================================================================="
echo "Benchmark Monitor"
echo "==================================================================="
echo ""

# Check if process is running
if ps aux | grep -q "[j]ulia.*benchmark"; then
    echo "✓ Benchmark process is RUNNING"
    echo ""
else
    echo "✗ No benchmark process found"
    echo ""
fi

# Show log file size
if [ -f "$LOG_FILE" ]; then
    echo "Log file size: $(ls -lh $LOG_FILE | awk '{print $5}')"
    echo ""
    
    echo "=== Recent Progress ==="
    tail -200 "$LOG_FILE" | grep -E "Progress:|Benchmarking:|Overall Result:|SUCCESS|FAILED" | tail -15
    echo ""
    
    echo "=== Summary So Far ==="
    if grep -q "BENCHMARK SUMMARY" "$LOG_FILE"; then
        grep -A 10 "BENCHMARK SUMMARY" "$LOG_FILE" | tail -15
    else
        echo "No summary yet - benchmark still running..."
    fi
else
    echo "Log file not found: $LOG_FILE"
fi

echo ""
echo "==================================================================="
echo "To follow live: tail -f $LOG_FILE"
echo "To stop: pkill -f 'julia.*benchmark'"
echo "==================================================================="
