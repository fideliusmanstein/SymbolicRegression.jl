#!/usr/bin/env julia
"""
benchmark_all_minimal.jl

Minimal benchmark of all 63 systems with:
- Very low iterations (3 for both stages)
- Reduced operator set (no sin, cos, exp)
- 3-minute timeout per system
"""

include("benchmark_ode_discovery.jl")

using .SymbolicRegressionODE
using .BenchmarkSystems

"""
    benchmark_single_with_timeout(problem_name, timeout_seconds=180)

Benchmark a single problem with timeout protection.

# Arguments
- `problem_name`: Name of the benchmark problem
- `timeout_seconds`: Maximum runtime (default: 180 = 3 minutes)

# Returns
- Result dictionary with timeout indicator
"""
function benchmark_single_with_timeout(problem_name; timeout_seconds=180)
    # Channel to receive result from async task
    result_channel = Channel{Dict}(1)
    
    # Task to run benchmark
    task = @async begin
        try
            result = benchmark_single_problem(
                problem_name,
                ode_options=ODERegressionOptions(
                    niterations_derivative=3,      # Very low iterations
                    niterations_integration=3,      # Very low iterations
                    complexity_derivative=10,
                    complexity_integration=10,
                    binary_operators=(+, *, -, /), # Keep basic operators
                    unary_operators=(),            # Remove sin, cos, exp
                    parallelism=:multithreading,
                    verbose=false
                )
            )
            put!(result_channel, result)
        catch e
            # Error during execution
            put!(result_channel, Dict(
                "problem_name" => problem_name,
                "success" => false,
                "discovery_time" => 0.0,
                "integration_loss" => Inf,
                "error" => string(e),
                "timeout" => false
            ))
        end
    end
    
    # Wait for result or timeout
    result = nothing
    start_time = time()
    
    while time() - start_time < timeout_seconds
        if isready(result_channel)
            result = take!(result_channel)
            break
        end
        sleep(0.1)
    end
    
    # Check if we timed out
    if result === nothing
        # Kill the task if still running
        try
            Base.throwto(task, InterruptException())
        catch
        end
        
        elapsed = time() - start_time
        result = Dict(
            "problem_name" => problem_name,
            "success" => false,
            "discovery_time" => elapsed,
            "integration_loss" => Inf,
            "error" => "TIMEOUT (exceeded $(timeout_seconds)s)",
            "timeout" => true
        )
        
        println("\n⏱ TIMEOUT after $(round(elapsed, digits=1))s")
    end
    
    return result
end

"""
    run_minimal_benchmark_all()

Run minimal benchmark on all 63 systems.
"""
function run_minimal_benchmark_all()
    println("\n" * "="^80)
    println("MINIMAL BENCHMARK: All 63 Systems")
    println("="^80)
    println("Configuration:")
    println("  - Iterations: 3 (derivative), 3 (integration)")
    println("  - Operators: +, *, -, / only (NO sin, cos, exp)")
    println("  - Timeout: 3 minutes per system")
    println("="^80)
    
    # Get all problems
    all_problems = BenchmarkSystems.list_problems()
    problem_names = sort(collect(keys(all_problems)))
    
    println("\nTotal systems to test: $(length(problem_names))")
    println("\nStarting benchmark...\n")
    
    # Run benchmarks
    all_results = []
    start_total = time()
    
    for (idx, problem_name) in enumerate(problem_names)
        println("\n" * "─"^80)
        println("[Progress: $idx/$(length(problem_names))] Testing: $problem_name")
        println("─"^80)
        
        problem_start = time()
        result = benchmark_single_with_timeout(problem_name; timeout_seconds=180)
        problem_time = time() - problem_start
        
        # Add to results
        push!(all_results, result)
        
        # Quick summary
        if get(result, "timeout", false)
            println("  Result: ⏱ TIMEOUT")
        elseif result["success"]
            println("  Result: ✓ SUCCESS (loss: $(round(result["integration_loss"], sigdigits=4)))")
        else
            println("  Result: ✗ FAILED (loss: $(result["integration_loss"]))")
        end
        println("  Time: $(round(problem_time, digits=1))s")
    end
    
    total_time = time() - start_total
    
    # Final summary
    println("\n\n" * "="^80)
    println("FINAL SUMMARY")
    println("="^80)
    
    successful = filter(r -> r["success"], all_results)
    failed = filter(r -> !r["success"] && !get(r, "timeout", false), all_results)
    timeouts = filter(r -> get(r, "timeout", false), all_results)
    errors = filter(r -> r["error"] !== nothing && !get(r, "timeout", false), all_results)
    
    println("Total systems tested: ", length(all_results))
    println("Successful: ", length(successful), " (", 
            round(100 * length(successful) / length(all_results), digits=1), "%)")
    println("Failed: ", length(failed), " (", 
            round(100 * length(failed) / length(all_results), digits=1), "%)")
    println("Timeouts: ", length(timeouts), " (", 
            round(100 * length(timeouts) / length(all_results), digits=1), "%)")
    println("Errors: ", length(errors))
    println("\nTotal runtime: ", round(total_time / 60, digits=1), " minutes")
    println("Average per system: ", round(total_time / length(all_results), digits=1), "s")
    
    # Save results
    timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
    results_dir = "results/benchmark_results"
    mkpath(results_dir)
    results_file = joinpath(results_dir, "minimal_benchmark_all_$(timestamp).txt")
    
    open(results_file, "w") do io
        println(io, "="^80)
        println(io, "MINIMAL BENCHMARK RESULTS - All 63 Systems")
        println(io, "Timestamp: ", Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))
        println(io, "="^80)
        println(io, "\nConfiguration:")
        println(io, "  - Derivative iterations: 3")
        println(io, "  - Integration iterations: 3")
        println(io, "  - Operators: +, *, -, / (NO sin, cos, exp)")
        println(io, "  - Timeout: 180s per system")
        println(io, "\n" * "="^80)
        println(io, "SUMMARY")
        println(io, "="^80)
        println(io, "Total systems: ", length(all_results))
        println(io, "Successful: ", length(successful), " (", 
                round(100 * length(successful) / length(all_results), digits=1), "%)")
        println(io, "Failed: ", length(failed), " (", 
                round(100 * length(failed) / length(all_results), digits=1), "%)")
        println(io, "Timeouts: ", length(timeouts), " (", 
                round(100 * length(timeouts) / length(all_results), digits=1), "%)")
        println(io, "Errors: ", length(errors))
        println(io, "\nTotal runtime: ", round(total_time / 60, digits=1), " minutes")
        
        println(io, "\n" * "="^80)
        println(io, "DETAILED RESULTS")
        println(io, "="^80)
        
        for result in all_results
            println(io, "\n", result["problem_name"])
            println(io, "  Success: ", result["success"])
            println(io, "  Time: ", round(result["discovery_time"], digits=2), "s")
            println(io, "  Integration loss: ", result["integration_loss"])
            if get(result, "timeout", false)
                println(io, "  Status: TIMEOUT")
            end
            if result["error"] !== nothing
                println(io, "  Error: ", result["error"])
            end
        end
    end
    
    println("\nResults saved to: $results_file")
    
    return all_results
end

# Run the benchmark if this script is executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    run_minimal_benchmark_all()
end
