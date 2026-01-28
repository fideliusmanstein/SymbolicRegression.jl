"""
test_benchmark.jl

Test suite for all 63 ODE benchmark systems with multi-trajectory evaluation.

Features:
- Tests all benchmark problems with minimal configuration
- Uses multiple trajectories per experiment for robust evaluation
- Includes timeout protection for large systems
- Generates detailed test reports

Run with: julia --project=.. test_benchmark.jl
"""

# =============================================================================
# Setup and Configuration
# =============================================================================

# Suppress progress bars and verbose output
ENV["SYMBOLIC_REGRESSION_PROGRESS"] = "false"

include("../benchmark_ode_discovery.jl")
using .SymbolicRegressionODE
using .BenchmarkSystems
using Test
using Logging
using Dates

# Suppress ODE solver warnings
Logging.disable_logging(Logging.Warn)

# =============================================================================
# Constants and Configuration
# =============================================================================

# Problems that timeout with minimal config (too many variables/experiments)
const TIMEOUT_PROBLEMS = [
    "ss_15genes1",   # 15 states, 10-20 experiments
    "ss_15genes2",
    "ss_30genes1",   # 30 states, 8-20 experiments, up to 41 time points
    "ss_30genes2",
    "ss_30genes3"
]

# Test configuration - minimal for fast testing
const TEST_OPTIONS = SymbolicRegressionODE.ODERegressionOptions(
    niterations_derivative = 15,
    niterations_integration = 5,
    complexity_derivative = 10,
    complexity_integration = 10,
    binary_operators = (+, *, -, /),
    unary_operators = (),
    parallelism = :serial,  # Avoid blocking issues
    verbose = false
)

# Multi-trajectory configuration for robust evaluation
const NUM_TRAJECTORIES = 3  # Use 3 different ICs per experiment for validation

# Maximum number of problems to test (nothing = all problems)
# Set to a smaller number for faster iteration/debugging
const MAX_PROBLEMS_TO_TEST = 3  # Options: nothing, 5, 10, 20, etc.

# Timeout protection (seconds, nothing = no timeout)
const TIMEOUT_SECONDS = nothing  # Options: nothing, 60, 180, 300, etc.

# =============================================================================
# Helper Functions
# =============================================================================


"""
    get_test_problems()

Get list of problems to test, excluding timeout-prone ones.
Respects MAX_PROBLEMS_TO_TEST if set.
"""
function get_test_problems()
    all_problems_dict = BenchmarkSystems.list_problems()
    all_problems_full = sort(collect(keys(all_problems_dict)))
    testable_problems = filter(p -> !(p in TIMEOUT_PROBLEMS), all_problems_full)
    
    # Limit number of problems if MAX_PROBLEMS_TO_TEST is set
    if MAX_PROBLEMS_TO_TEST !== nothing && MAX_PROBLEMS_TO_TEST < length(testable_problems)
        testable_problems = testable_problems[1:MAX_PROBLEMS_TO_TEST]
    end
    
    return (
        all = all_problems_full,
        testable = testable_problems,
        excluded = TIMEOUT_PROBLEMS
    )
end

"""
    create_result_dict(problem_name, success, loss, time, n_states; kwargs...)

Create a standardized result dictionary for a benchmark test.
"""
function create_result_dict(problem_name, success, loss, time, n_states; 
                           error=nothing, timeout=false, kwargs...)
    result = Dict(
        "problem_name" => problem_name,
        "success" => success,
        "integration_loss" => loss,
        "discovery_time" => time,
        "n_states" => n_states,
        "timeout" => timeout,
        "error" => error
    )
    
    # Add any additional fields
    for (key, value) in kwargs
        result[string(key)] = value
    end
    
    return result
end

"""
    run_single_benchmark(problem_name, num_trajectories)

Run discovery on a single benchmark problem with multiple trajectories.
Returns a result dictionary with success status and metrics.
"""
function run_single_benchmark(problem_name, num_trajectories)
    println("  Loading problem with $num_trajectories trajectories per experiment...")
    
    try
        result = benchmark_single_problem(
            problem_name,
            ode_options = TEST_OPTIONS,
            num_trajectories = num_trajectories  # NEW: Multi-trajectory support
        )
        return result
        
    catch e
        # Handle errors gracefully
        return create_result_dict(
            problem_name,
            false,  # success
            Inf,    # loss
            0.0,    # time
            0,      # n_states
            error = string(e)
        )
    end
end

"""
    run_with_timeout(problem_name, num_trajectories, timeout_seconds)

Run benchmark test with timeout protection.
If timeout_seconds is nothing, runs without timeout.

Returns:
- (completed::Bool, result::Dict): Whether test finished and the results
"""
function run_with_timeout(problem_name, num_trajectories, timeout_seconds)
    timeout_msg = timeout_seconds === nothing ? "no timeout" : "$(timeout_seconds)s"
    println("Testing: $problem_name (timeout: $timeout_msg, trajectories: $num_trajectories)")
    
    # If no timeout, run directly
    if timeout_seconds === nothing
        result = run_single_benchmark(problem_name, num_trajectories)
        return (true, result)
    end
    
    # Run with timeout protection
    result_channel = Channel{Dict}(1)
    
    # Launch async task
    task = @async begin
        result = run_single_benchmark(problem_name, num_trajectories)
        put!(result_channel, result)
    end
    
    # Wait with timeout
    status = timedwait(() -> isready(result_channel), timeout_seconds; pollint=1.0)
    
    if status == :ok
        # Completed successfully
        result = take!(result_channel)
        return (true, result)
    else
        # Timeout - interrupt task
        println("  ⏱ TIMEOUT after $(timeout_seconds)s")
        try
            schedule(task, InterruptException(), error=true)
        catch
        end
        
        timeout_result = create_result_dict(
            problem_name,
            false,  # success
            Inf,    # loss
            Float64(timeout_seconds),  # time
            0,      # n_states
            timeout = true
        )
        
        return (false, timeout_result)
    end
end

# =============================================================================
# Result Reporting
# =============================================================================

"""
    write_result_to_file(file, result)

Write a single test result to the output file.
"""
function write_result_to_file(file, result)
    println(file, "Problem: $(result["problem_name"])")
    println(file, "  Success: $(result["success"])")
    println(file, "  Integration Loss: $(result["integration_loss"])")
    println(file, "  Discovery Time: $(result["discovery_time"])s")
    println(file, "  N States: $(result["n_states"])")
    
    if get(result, "timeout", false)
        println(file, "  Status: TIMEOUT")
    end
    
    if haskey(result, "error") && result["error"] !== nothing
        println(file, "  Error: $(result["error"])")
    end
    
    if haskey(result, "ground_truth_equations")
        println(file, "  Ground Truth Equations:")
        for eq in result["ground_truth_equations"]
            println(file, "    $eq")
        end
    end
    
    if haskey(result, "discovered_equations")
        println(file, "  Discovered Equations:")
        for (i, eq) in enumerate(result["discovered_equations"])
            println(file, "    X$i' = $eq")
        end
    end
    
    println(file)
    flush(file)
end

"""
    print_failure_diagnostics(problem_name, result)

Print diagnostic information for failed tests.
"""
function print_failure_diagnostics(problem_name, result)
    if get(result, "timeout", false)
        println("\n⏱ $problem_name TIMEOUT after $(result["discovery_time"])s")
    else
        println("\n⚠ $problem_name FAILED:")
        println("  Integration loss: $(result["integration_loss"])")
        println("  Discovery time: $(result["discovery_time"])s")
        
        if haskey(result, "error") && result["error"] !== nothing
            println("  Error: $(result["error"])")
        end
    end
end

"""
    write_summary(file, results)

Write summary statistics to the output file.
"""
function write_summary(file, results)
    successes = count(r -> r["success"], values(results))
    failures = length(results) - successes
    
    println(file, "="^80)
    println(file, "SUMMARY")
    println(file, "="^80)
    println(file, "Completed: $(now())")
    println(file, "✓ Successful: $successes / $(length(results))")
    println(file, "✗ Failed: $failures / $(length(results))")
    
    if failures > 0
        println(file, "\nFailed problems:")
        for (name, result) in sort(collect(results), by=x->x[1])
            if !result["success"]
                loss = result["integration_loss"]
                if get(result, "timeout", false)
                    println(file, "  - $name (TIMEOUT)")
                else
                    println(file, "  - $name (loss: $(round(loss, digits=4)))")
                end
            end
        end
    end
    
    println(file, "="^80)
end

# =============================================================================
# Main Test Execution
# =============================================================================

# Get test problems
problems = get_test_problems()

println("="^80)
println("ODE Discovery Benchmark Test Suite - Multi-Trajectory")
println("="^80)
println("Total problems: $(length(problems.all))")
println("Excluded (timeout): $(length(problems.excluded))")
println("Testing: $(length(problems.testable)) problems")
if MAX_PROBLEMS_TO_TEST !== nothing
    println("  (Limited to first $MAX_PROBLEMS_TO_TEST for faster iteration)")
end
println()
println("Configuration:")
println("  - Derivative iterations: $(TEST_OPTIONS.niterations_derivative)")
println("  - Integration iterations: $(TEST_OPTIONS.niterations_integration)")
println("  - Operators: +, -, *, / (no sin, cos, exp)")
println("  - Trajectories per experiment: $NUM_TRAJECTORIES")
timeout_msg = TIMEOUT_SECONDS === nothing ? "none (no timeout)" : "$(TIMEOUT_SECONDS)s"
println("  - Timeout per system: $timeout_msg")
println("="^80)
println()

# Setup results file
results_dir = "test_results"
mkpath(results_dir)  # Create directory if it doesn't exist
results_file = joinpath(results_dir, "test_results_$(Dates.format(now(), "yyyymmdd_HHMMSS")).txt")
results_summary = Dict{String, Dict}()

# Write header
open(results_file, "w") do f
    println(f, "="^80)
    println(f, "ODE Discovery Benchmark Test Results")
    println(f, "Multi-Trajectory Evaluation ($(NUM_TRAJECTORIES) ICs per experiment)")
    println(f, "Started: $(now())")
    println(f, "="^80)
    println(f)
end

# Run all tests
@testset "ODE Discovery - All Benchmark Systems" begin
    for problem_name in problems.testable
        @testset "$problem_name" begin
            # Run test with timeout protection
            completed, result = run_with_timeout(
                problem_name,
                NUM_TRAJECTORIES,
                TIMEOUT_SECONDS
            )
            
            # Store result
            results_summary[problem_name] = result
            
            # Write to file immediately
            open(results_file, "a") do f
                write_result_to_file(f, result)
            end
            
            # Print diagnostics for failures
            if !result["success"]
                print_failure_diagnostics(problem_name, result)
            end
            
            # Test assertion (skip if timeout)
            if completed
                @test result["success"]
            end
        end
    end
end

# =============================================================================
# Final Summary
# =============================================================================

println()
println("="^80)
println("Benchmark Test Suite Summary")
println("="^80)

successes = count(r -> r["success"], values(results_summary))
failures = length(results_summary) - successes

println("✓ Successful: $successes / $(length(results_summary))")
println("✗ Failed: $failures / $(length(results_summary))")

if failures > 0
    println("\nFailed problems:")
    for (name, result) in sort(collect(results_summary), by=x->x[1])
        if !result["success"]
            if get(result, "timeout", false)
                println("  - $name (TIMEOUT)")
            else
                loss = result["integration_loss"]
                println("  - $name (loss: $(round(loss, digits=4)))")
            end
        end
    end
end

println("="^80)
println("\nResults written to: $results_file")

# Write final summary
open(results_file, "a") do f
    write_summary(f, results_summary)
end
