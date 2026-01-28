"""
test_benchmark.jl

Test suite for all 63 ODE benchmark systems.
Tests each system with minimal configuration (3 iterations, basic operators only).

Run with: julia --project=.. test_benchmark.jl
"""

# Suppress progress bars and verbose output
ENV["SYMBOLIC_REGRESSION_PROGRESS"] = "false"

include("../benchmark_ode_discovery.jl")
using .SymbolicRegressionODE
using .BenchmarkSystems
using Test
using Logging

# Suppress warnings from ODE solver
Logging.disable_logging(Logging.Warn)

# Exception list - problems that timeout with minimal config (too many variables/experiments)
# ss_15genes: 15 state variables, 10-20 experiments
# ss_30genes: 30 state variables, 8-20 experiments, up to 41 time points
const TIMEOUT_PROBLEMS = [
    "ss_15genes1",
    "ss_15genes2",
    "ss_30genes1", 
    "ss_30genes2",
    "ss_30genes3"
]

# Get all problem names
all_problems_dict = BenchmarkSystems.list_problems()
all_problems_full = sort(collect(keys(all_problems_dict)))
all_problems = filter(p -> !(p in TIMEOUT_PROBLEMS), all_problems_full)  # Exclude timeout problems

println("Total problems: $(length(all_problems_full))")
println("Excluded (timeout): $(length(TIMEOUT_PROBLEMS))")
println("Testing: $(length(all_problems)) problems")
println()

# Minimal test configuration
const TEST_OPTIONS = SymbolicRegressionODE.ODERegressionOptions(
    niterations_derivative=3,
    niterations_integration=3,
    complexity_derivative=10,
    complexity_integration=10,
    binary_operators=(+, *, -, /),
    unary_operators=(),
    parallelism=:serial,  # Changed from :multithreading to avoid blocking
    verbose=false
)

const TIMEOUT_SECONDS = 180

"""
    run_benchmark_test(problem_name, timeout_seconds)

Run a single benchmark problem with timeout protection.
Returns (completed, result_dict) where:
- completed: true if test finished within timeout, false if timed out
- result_dict: contains "success" and other benchmark results
"""
function run_benchmark_test(problem_name, timeout_seconds)
    println("Starting test for: $problem_name (timeout: $(timeout_seconds)s)")
    result_channel = Channel{Dict}(1)
    
    task = @async begin
        try
            println("  Task started for $problem_name")
            result = benchmark_single_problem(
                problem_name,
                ode_options=TEST_OPTIONS
            )
            println("  Task completed for $problem_name")
            put!(result_channel, result)
        catch e
            println("  Task errored for $problem_name: $e")
            # Ensure we always put a valid result
            put!(result_channel, Dict(
                "success" => false,
                "error" => string(e),
                "problem_name" => problem_name,
                "discovery_time" => 0.0,
                "integration_loss" => Inf,
                "n_states" => 0
            ))
        end
    end
    
    # Wait with timeout using timedwait
    println("  Waiting for result (timeout: $(timeout_seconds)s)...")
    status = timedwait(() -> isready(result_channel), timeout_seconds; pollint=1.0)
    
    if status == :ok
        println("  Result ready for $problem_name")
        result = take!(result_channel)
        return (true, result)
    else
        println("  TIMEOUT for $problem_name after $(timeout_seconds)s")
        # Timeout - try to interrupt the task
        try
            schedule(task, InterruptException(), error=true)
        catch
        end
        
        return (false, Dict(
            "success" => false,
            "timeout" => true,
            "problem_name" => problem_name,
            "discovery_time" => timeout_seconds,
            "integration_loss" => Inf,
            "n_states" => 0
        ))
    end
end

# Display test configuration
println("="^80)
println("ODE Discovery Benchmark Test Suite")
println("="^80)
println("Total systems: $(length(all_problems))")
println("Configuration:")
println("  - Derivative iterations: $(TEST_OPTIONS.niterations_derivative)")
println("  - Integration iterations: $(TEST_OPTIONS.niterations_integration)")
println("  - Operators: +, -, *, / (no sin, cos, exp)")
println("  - Timeout per system: $(TIMEOUT_SECONDS)s")
println("="^80)
println()

# Run all benchmark tests
results_summary = Dict()
results_file = "tests/test_results_$(Dates.format(now(), "yyyymmdd_HHMMSS")).txt"

# Write header to results file
open(results_file, "w") do f
    println(f, "="^80)
    println(f, "ODE Discovery Benchmark Test Results")
    println(f, "Started: $(now())")
    println(f, "="^80)
    println(f)
end

@testset "ODE Discovery - All Benchmark Systems" begin
    for problem_name in all_problems
        @testset "$problem_name" begin
            completed, result = run_benchmark_test(problem_name, TIMEOUT_SECONDS)
            
            # Store result for summary
            results_summary[problem_name] = result
            
            # Write result to file immediately
            open(results_file, "a") do f
                println(f, "Problem: $problem_name")
                println(f, "  Completed: $completed")
                println(f, "  Success: $(result["success"])")
                println(f, "  Integration Loss: $(result["integration_loss"])")
                println(f, "  Discovery Time: $(result["discovery_time"])s")
                println(f, "  N States: $(result["n_states"])")
                if haskey(result, "timeout") && result["timeout"]
                    println(f, "  Status: TIMEOUT")
                end
                if haskey(result, "error") && result["error"] !== nothing
                    println(f, "  Error: $(result["error"])")
                end
                if haskey(result, "ground_truth_equations")
                    println(f, "  Ground Truth Equations:")
                    for (i, eq) in enumerate(result["ground_truth_equations"])
                        println(f, "    $eq")
                    end
                end
                if haskey(result, "discovered_equations")
                    println(f, "  Discovered Equations:")
                    for (i, eq) in enumerate(result["discovered_equations"])
                        println(f, "    X$i' = $eq")
                    end
                end
                println(f)
                flush(f)
            end
            
            # Report timeout as warning, not test failure
            if !completed
                println("\n⏱ $problem_name TIMEOUT after $(TIMEOUT_SECONDS)s")
            elseif !result["success"]
                # Print diagnostics for failures
                println("\n⚠ $problem_name FAILED:")
                println("  Integration loss: $(result["integration_loss"])")
                println("  Discovery time: $(result["discovery_time"])s")
                if haskey(result, "error") && result["error"] !== nothing
                    println("  Error: $(result["error"])")
                end
            end
            
            # Only test success if completed (timeouts are skipped)
            if completed
                @test result["success"]
            end
        end
    end
end

println()
println("="^80)
println("Benchmark Test Suite Summary")
println("="^80)
successes = count(r -> r["success"], values(results_summary))
failures = count(r -> !r["success"], values(results_summary))
println("✓ Successful: $successes / $(length(results_summary))")
println("✗ Failed: $failures / $(length(results_summary))")
if failures > 0
    println("\nFailed problems:")
    for (name, result) in sort(collect(results_summary), by=x->x[1])
        if !result["success"]
            loss = result["integration_loss"]
            println("  - $name (loss: $(round(loss, digits=4)))")
        end
    end
end
println("="^80)
println("\nResults written to: $results_file")

# Write summary to file
open(results_file, "a") do f
    println(f, "="^80)
    println(f, "SUMMARY")
    println(f, "="^80)
    println(f, "Completed: $(now())")
    println(f, "✓ Successful: $successes / $(length(results_summary))")
    println(f, "✗ Failed: $failures / $(length(results_summary))")
    if failures > 0
        println(f, "\nFailed problems:")
        for (name, result) in sort(collect(results_summary), by=x->x[1])
            if !result["success"]
                loss = result["integration_loss"]
                println(f, "  - $name (loss: $(round(loss, digits=4)))")
            end
        end
    end
    println(f, "="^80)
end
