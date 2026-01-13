#!/usr/bin/env julia

# Test all problem routing in get_ground_truth_equations
include("benchmark_ode_discovery.jl")

# Extract all problem names from BenchmarkSystems
all_problems = collect(keys(BenchmarkSystems.list_problems()))
sort!(all_problems)

println("Testing routing for all $(length(all_problems)) problems...\n")

errors = []
for problem in all_problems
    try
        equations = get_ground_truth_equations(problem)
        if any(startswith(eq, "Ground truth equations not yet implemented") || 
               startswith(eq, "Unknown problem") for eq in equations)
            push!(errors, (problem, "Not implemented or unknown"))
        else
            println("✓ $problem: $(length(equations)) equations")
        end
    catch e
        push!(errors, (problem, string(e)))
        println("✗ $problem: ERROR - $e")
    end
end

if !isempty(errors)
    println("\n" * "="^60)
    println("ERRORS FOUND:")
    println("="^60)
    for (problem, error) in errors
        println("  $problem: $error")
    end
else
    println("\n" * "="^60)
    println("All problems routed successfully!")
    println("="^60)
end
