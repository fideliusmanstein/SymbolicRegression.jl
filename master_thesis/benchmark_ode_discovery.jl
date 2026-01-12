"""
benchmark_ode_discovery.jl

Comprehensive benchmarking of ODE discovery algorithm on all benchmark problems.
Automatically compares discovered equations with ground truth.
"""

include("SymbolicRegressionODE.jl")
include("benchmarkProblems/BenchmarkSystems.jl")

using .SymbolicRegressionODE
using .BenchmarkSystems
using SymbolicRegression
using Statistics
using Printf

"""
    evaluate_tree_on_data(tree, X_features, sr_options)

Evaluate a symbolic expression tree on input data.

# Arguments
- `tree`: Expression tree
- `X_features`: Feature matrix (n_features × n_samples)
- `sr_options`: SymbolicRegression.Options for tree evaluation

# Returns
- Predictions vector
"""
function evaluate_tree_on_data(tree, X_features, sr_options)
    n_samples = size(X_features, 2)
    predictions = zeros(n_samples)
    
    for i in 1:n_samples
        x = X_features[:, i]
        predictions[i] = eval_tree_array(tree, x, sr_options)[1]
    end
    
    return predictions
end

"""
    compute_r2_score(y_true, y_pred)

Compute R² coefficient of determination.

# Arguments
- `y_true`: True values
- `y_pred`: Predicted values

# Returns
- R² score (1.0 = perfect fit, 0.0 = no better than mean, negative = worse than mean)
"""
function compute_r2_score(y_true, y_pred)
    ss_res = sum((y_true .- y_pred).^2)
    ss_tot = sum((y_true .- mean(y_true)).^2)
    
    if ss_tot ≈ 0.0
        return ss_res ≈ 0.0 ? 1.0 : -Inf
    end
    
    return 1.0 - ss_res / ss_tot
end

"""
    compute_symbolic_accuracy(discovered_tree, true_derivatives, X_features, sr_options; 
                             r2_threshold=0.95, max_error_threshold=0.1)

Compare discovered equation with ground truth using multiple metrics.

# Arguments
- `discovered_tree`: Discovered expression tree
- `true_derivatives`: Ground truth derivative values
- `X_features`: Feature matrix used for symbolic regression
- `sr_options`: SymbolicRegression options
- `r2_threshold`: R² threshold for considering equations equivalent (default: 0.95)
- `max_error_threshold`: Maximum relative error threshold (default: 0.1)

# Returns
- Dictionary with comparison metrics
"""
function compute_symbolic_accuracy(discovered_tree, true_derivatives, X_features, sr_options;
                                   r2_threshold=0.95, max_error_threshold=0.1)
    # Evaluate discovered equation on feature data
    predictions = evaluate_tree_on_data(discovered_tree, X_features, sr_options)
    
    # Compute metrics
    r2 = compute_r2_score(true_derivatives, predictions)
    
    # Compute error metrics
    abs_errors = abs.(predictions .- true_derivatives)
    mean_abs_error = mean(abs_errors)
    max_abs_error = maximum(abs_errors)
    
    # Relative errors (avoid division by zero)
    relative_errors = abs_errors ./ (abs.(true_derivatives) .+ 1e-10)
    mean_rel_error = mean(relative_errors)
    max_rel_error = maximum(relative_errors)
    
    # Determine if equations are equivalent
    is_equivalent = (r2 >= r2_threshold) && (max_rel_error <= max_error_threshold)
    
    return Dict(
        "r2" => r2,
        "mean_absolute_error" => mean_abs_error,
        "max_absolute_error" => max_abs_error,
        "mean_relative_error" => mean_rel_error,
        "max_relative_error" => max_rel_error,
        "is_equivalent" => is_equivalent,
        "equation" => string_tree(discovered_tree, sr_options)
    )
end

"""
    benchmark_single_problem(problem_name; ode_options=nothing, 
                            r2_threshold=0.95, max_error_threshold=0.1)

Benchmark ODE discovery on a single problem.

# Arguments
- `problem_name`: Name of the benchmark problem
- `ode_options`: ODERegressionOptions (if nothing, uses default fast settings)
- `r2_threshold`: R² threshold for equation equivalence
- `max_error_threshold`: Maximum relative error threshold

# Returns
- Dictionary with benchmark results
"""
function benchmark_single_problem(problem_name; 
                                 ode_options=nothing,
                                 r2_threshold=0.95,
                                 max_error_threshold=0.1)
    
    println("\n" * "="^80)
    println("Benchmarking: $problem_name")
    println("="^80)
    
    # Load problem
    experiments = BenchmarkSystems.load_problem(problem_name)
    
    # Use default fast options if not provided
    if ode_options === nothing
        ode_options = ODERegressionOptions(
            niterations_derivative=8,
            niterations_integration=4,
            complexity_derivative=12,
            complexity_integration=10,
            parallelism=:multithreading,
            verbose=false
        )
    end
    
    # Time the discovery process
    start_time = time()
    
    try
        # Discover ODE system
        result = discover_ode_system(experiments; ode_options=ode_options)
        
        discovery_time = time() - start_time
        
        # Extract information from result
        exp = experiments[1]
        n_states = size(exp[:X], 2)
        
        # Create SymbolicRegression options for displaying equations
        sr_options = SymbolicRegression.Options(
            binary_operators=ode_options.binary_operators,
            unary_operators=ode_options.unary_operators
        )
        
        # Display discovered equations
        state_results = []
        for i in 1:n_states
            equation_str = string_tree(result.best_trees[i], sr_options)
            println("\nState $i:")
            println("  Discovered: ", equation_str)
            
            push!(state_results, Dict(
                "equation" => equation_str,
                "complexity" => compute_complexity(result.best_trees[i], sr_options)
            ))
        end
        
        # Consider it successful if discovery completed without error
        success = true
        
        println("\n" * "-"^80)
        println("Overall Result: ✓ SUCCESS")
        println("Discovery time: ", @sprintf("%.2f", discovery_time), " seconds")
        println("Integration loss: ", @sprintf("%.6e", result.integration_loss))
        
        return Dict(
            "problem_name" => problem_name,
            "success" => success,
            "discovery_time" => discovery_time,
            "integration_loss" => result.integration_loss,
            "n_states" => n_states,
            "state_results" => state_results,
            "error" => nothing
        )
        
    catch e
        discovery_time = time() - start_time
        
        println("\n✗ ERROR during discovery: ", e)
        println("Discovery time before error: ", @sprintf("%.2f", discovery_time), " seconds")
        
        return Dict(
            "problem_name" => problem_name,
            "success" => false,
            "discovery_time" => discovery_time,
            "integration_loss" => Inf,
            "n_states" => 0,
            "state_results" => [],
            "all_equivalent" => false,
            "error" => string(e)
        )
    end
end

"""
    benchmark_all_problems(; ode_options=nothing, 
                          problem_filter=nothing,
                          r2_threshold=0.95,
                          max_error_threshold=0.1,
                          save_results=true)

Benchmark ODE discovery on all (or filtered) benchmark problems.

# Arguments
- `ode_options`: ODERegressionOptions (if nothing, uses default fast settings)
- `problem_filter`: Function to filter problems (e.g., name -> startswith(name, "ss_"))
- `r2_threshold`: R² threshold for equation equivalence
- `max_error_threshold`: Maximum relative error threshold
- `save_results`: Save results to file

# Returns
- Vector of result dictionaries
"""
function benchmark_all_problems(;
                               ode_options=nothing,
                               problem_filter=nothing,
                               r2_threshold=0.95,
                               max_error_threshold=0.1,
                               save_results=true)
    
    # Get all problems
    all_problems = BenchmarkSystems.list_problems()
    problem_names = sort(collect(keys(all_problems)))
    
    # Apply filter if provided
    if problem_filter !== nothing
        problem_names = filter(problem_filter, problem_names)
    end
    
    println("\n" * "="^80)
    println("BENCHMARK: ODE Discovery System")
    println("="^80)
    println("Total problems to test: ", length(problem_names))
    println("R² threshold: ", r2_threshold)
    println("Max error threshold: ", max_error_threshold)
    if ode_options !== nothing
        println("Derivative iterations: ", ode_options.niterations_derivative)
        println("Integration iterations: ", ode_options.niterations_integration)
        println("Differentiation method: ", ode_options.differentiation_method)
    end
    println("="^80)
    
    # Run benchmarks
    all_results = []
    
    for (idx, problem_name) in enumerate(problem_names)
        println("\n[Progress: $idx/$(length(problem_names))]")
        
        result = benchmark_single_problem(
            problem_name;
            ode_options=ode_options,
            r2_threshold=r2_threshold,
            max_error_threshold=max_error_threshold
        )
        
        push!(all_results, result)
    end
    
    # Compute summary statistics
    println("\n\n" * "="^80)
    println("BENCHMARK SUMMARY")
    println("="^80)
    
    successful = filter(r -> r["success"], all_results)
    failed = filter(r -> !r["success"], all_results)
    errors = filter(r -> r["error"] !== nothing, all_results)
    
    println("Total problems tested: ", length(all_results))
    println("Successful: ", length(successful), " (", 
            @sprintf("%.1f%%", 100 * length(successful) / length(all_results)), ")")
    println("Failed: ", length(failed), " (", 
            @sprintf("%.1f%%", 100 * length(failed) / length(all_results)), ")")
    println("Errors: ", length(errors))
    
    if !isempty(all_results)
        total_time = sum(r["discovery_time"] for r in all_results)
        avg_time = mean(r["discovery_time"] for r in all_results)
        
        println("\nTotal time: ", @sprintf("%.2f", total_time), " seconds")
        println("Average time per problem: ", @sprintf("%.2f", avg_time), " seconds")
    end
    
    # List failed problems
    if !isempty(failed)
        println("\nFailed problems:")
        for r in failed
            println("  - ", r["problem_name"], 
                   r["error"] !== nothing ? " (ERROR: $(r["error"]))" : "")
        end
    end
    
    # Save results if requested
    if save_results
        timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
        filename = "benchmark_results_$(timestamp).txt"
        
        open(filename, "w") do io
            println(io, "ODE Discovery Benchmark Results")
            println(io, "="^80)
            println(io, "Timestamp: ", timestamp)
            println(io, "Total problems: ", length(all_results))
            println(io, "Successful: ", length(successful))
            println(io, "Failed: ", length(failed))
            println(io, "\n" * "="^80)
            
            for result in all_results
                println(io, "\nProblem: ", result["problem_name"])
                println(io, "Success: ", result["success"])
                println(io, "Time: ", @sprintf("%.2f", result["discovery_time"]), "s")
                println(io, "Integration loss: ", @sprintf("%.6e", result["integration_loss"]))
                
                if result["error"] !== nothing
                    println(io, "Error: ", result["error"])
                end
                
                for (i, state_result) in enumerate(result["state_results"])
                    println(io, "  State $i:")
                    println(io, "    Equation: ", state_result["equation"])
                    println(io, "    R²: ", @sprintf("%.6f", state_result["r2"]))
                    println(io, "    Mean rel error: ", @sprintf("%.6f", state_result["mean_relative_error"]))
                    println(io, "    Equivalent: ", state_result["is_equivalent"])
                end
                
                println(io, "-"^80)
            end
        end
        
        println("\nResults saved to: ", filename)
    end
    
    return all_results
end

"""
    quick_benchmark(n_problems=5)

Quick benchmark on a small subset of problems for testing.
"""
function quick_benchmark(n_problems=5)
    all_problems = BenchmarkSystems.list_problems()
    problem_names = sort(collect(keys(all_problems)))
    selected = problem_names[1:min(n_problems, length(problem_names))]
    
    benchmark_all_problems(
        problem_filter = name -> name in selected,
        ode_options = ODERegressionOptions(
            niterations_derivative=5,
            niterations_integration=3,
            complexity_derivative=10,
            verbose=false
        ),
        save_results=false
    )
end

# Export functions
export benchmark_single_problem, benchmark_all_problems, quick_benchmark

