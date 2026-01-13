#!/usr/bin/env julia

# Quick script to run benchmark on 3 examples
include("benchmark_ode_discovery.jl")

println("Running quick benchmark on 3 problems...")
results = quick_benchmark(3)

println("\n" * "="^60)
println("RESULTS SUMMARY:")
println("="^60)
for (i, result) in enumerate(results)
    status = result[:success] ? "✓ PASS" : "✗ FAIL"
    println("$status $(result[:problem]): $(result[:time])s, loss=$(result[:integration_loss])")
end
