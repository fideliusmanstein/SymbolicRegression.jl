#!/bin/bash
# Quick status check for benchmark

if ps aux | grep -q "[j]ulia.*benchmark"; then
    echo "✓ Benchmark RUNNING"
    ps aux | grep "[j]ulia.*benchmark" | awk '{print "  Runtime: "$10"  CPU: "$3"%  Memory: "$6" KB"}'
    echo "  Log size: $(ls -lh benchmark_full.log 2>/dev/null | awk '{print $5}')"
else
    echo "✗ Benchmark NOT running"
    if [ -f benchmark_full.log ]; then
        echo "  Log exists ($(ls -lh benchmark_full.log | awk '{print $5}'))"
        if grep -q "Full benchmark complete" benchmark_full.log 2>/dev/null; then
            echo "  Status: COMPLETED"
        else
            echo "  Status: Stopped/Failed"
        fi
    fi
fi

# Check for results file
RESULTS=$(ls -t benchmark_results_*.txt 2>/dev/null | head -1)
if [ -n "$RESULTS" ]; then
    echo "  Latest results: $RESULTS"
fi
