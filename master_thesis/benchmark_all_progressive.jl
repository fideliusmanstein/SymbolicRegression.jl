"""
Progressive Benchmark Script - Runs all 63 ODE Systems
Loads each problem individually to avoid compilation hang
"""

include("benchmark_ode_discovery.jl")
using .SymbolicRegressionODE
using .BenchmarkSystems
using Dates

# Redirect output
log_file = open("benchmark_progressive_run.log", "w")
original_stdout = stdout
redirect_stdout(log_file)

println("=" ^ 80)
println("PROGRESSIVE BENCHMARK: All 63 Systems")
println("=" ^ 80)
println("\nConfiguration:")
println("  - Iterations: 3 (derivative), 3 (integration)")
println("  - Operators: +, *, -, / only (NO sin, cos, exp)")
println("  - Timeout: 3 minutes per system")
println("\nStarting at: ", Dates.now())
println("=" ^ 80)
flush(log_file)

# Define the options
ode_options = ODERegressionOptions(
    niterations_derivative=3,
    niterations_integration=3,
    complexity_derivative=10,
    complexity_integration=10,
    binary_operators=(+, *, -, /),
    unary_operators=(),
    parallelism=:multithreading,
    verbose=false
)

# Get all problem names
all_problems_dict = BenchmarkSystems.list_problems()
all_problems = sort(collect(keys(all_problems_dict)))

println("\nTotal systems to test: ", length(all_problems))
println("\nProblems to run:")
for (i, name) in enumerate(all_problems)
    println("  $i. $name")
end
println("\n" * "=" ^ 80)
flush(log_file)

# Results storage
results = Dict{String, Any}()
successful_count = 0
failed_count = 0
timeout_count = 0

# Run each problem with timeout
for (i, problem_name) in enumerate(all_problems)
    println("\n" * "=" ^ 80)
    println("[$i/$(length(all_problems))] Testing: $problem_name")
    println("=" ^ 80)
    flush(log_file)
    
    result_channel = Channel{Dict}(1)
    
    # Create async task with timeout
    task = @async begin
        try
            result = benchmark_single_problem(
                problem_name,
                ode_options=ode_options
            )
            put!(result_channel, result)
        catch e
            println("ERROR in $problem_name: ", e)
            flush(log_file)
            put!(result_channel, Dict("success" => false, "error" => string(e)))
        end
    end
    
    # Wait with timeout (180 seconds = 3 minutes)
    timeout_seconds = 180
    timed_out = false
    result = nothing
    
    start_time = time()
    while time() - start_time < timeout_seconds
        if isready(result_channel)
            result = take!(result_channel)
            break
        end
        sleep(0.5)
    end
    
    if result === nothing
        timed_out = true
        println("⏱  TIMEOUT after $timeout_seconds seconds")
        global timeout_count += 1
        results[problem_name] = Dict("status" => "timeout")
    else
        if result["success"]
            println("✓ SUCCESS")
            println("  Integration loss: ", result["integration_loss"])
            println("  Time: ", result["discovery_time"], " seconds")
            global successful_count += 1
            results[problem_name] = Dict(
                "status" => "success",
                "loss" => result["integration_loss"],
                "time" => result["discovery_time"]
            )
        else
            println("✗ FAILED")
            if haskey(result, "error")
                println("  Error: ", result["error"])
            end
            global failed_count += 1
            results[problem_name] = Dict("status" => "failed", "error" => get(result, "error", "unknown"))
        end
    end
    flush(log_file)
end

# Summary
println("\n" * "=" ^ 80)
println("FINAL SUMMARY")
println("=" ^ 80)
println("\nTotal systems tested: ", length(all_problems))
println("✓ Successful: $successful_count")
println("✗ Failed: $failed_count")
println("⏱  Timeout: $timeout_count")

if successful_count > 0
    println("\n" * "-" ^ 40)
    println("Successful Systems:")
    for (name, res) in results
        if res["status"] == "success"
            println("  ✓ $name: loss=$(res["loss"]), time=$(res["time"])s")
        end
    end
end

if failed_count > 0
    println("\n" * "-" ^ 40)
    println("Failed Systems:")
    for (name, res) in results
        if res["status"] == "failed"
            error_msg = get(res, "error", "unknown")
            println("  ✗ $name: $error_msg")
        end
    end
end

if timeout_count > 0
    println("\n" * "-" ^ 40)
    println("Timeout Systems:")
    for (name, res) in results
        if res["status"] == "timeout"
            println("  ⏱  $name")
        end
    end
end

println("\n" * "=" ^ 80)
println("Completed at: ", Dates.now())
println("=" ^ 80)

close(log_file)
redirect_stdout(original_stdout)

println("\nBenchmark complete! Results saved to: benchmark_progressive_run.log")
