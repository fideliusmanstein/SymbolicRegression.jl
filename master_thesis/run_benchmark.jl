"""
run_benchmark.jl

Simple script to run ODE discovery benchmarks.
"""

include("benchmark_ode_discovery.jl")

using .SymbolicRegressionODE
using Dates

# Example 1: Quick test on first 3 problems
println("="^80)
println("EXAMPLE 1: Quick Benchmark (3 problems)")
println("="^80)
quick_benchmark(3)

# Example 2: Benchmark specific problem category
println("\n\n" * "="^80)
println("EXAMPLE 2: Benchmark Simple Problems")
println("="^80)

results_simple = benchmark_all_problems(
    problem_filter = name -> startswith(name, "simpleLin") || startswith(name, "simpleFb"),
    ode_options = ODERegressionOptions(
        niterations_derivative=10,
        niterations_integration=5,
        complexity_derivative=12,
        differentiation_method=:finite_difference,
        verbose=false
    ),
    r2_threshold=0.95,
    max_error_threshold=0.1,
    save_results=true
)

# Example 3: Compare differentiation methods on single problem
println("\n\n" * "="^80)
println("EXAMPLE 3: Comparing Differentiation Methods")
println("="^80)

println("\n--- Using Finite Differences ---")
result_fd = benchmark_single_problem(
    "simpleLin1",
    ode_options=ODERegressionOptions(
        differentiation_method=:finite_difference,
        niterations_derivative=10,
        niterations_integration=5,
        verbose=false
    )
)

println("\n--- Using Savitzky-Golay ---")
result_sg = benchmark_single_problem(
    "simpleLin1",
    ode_options=ODERegressionOptions(
        differentiation_method=:savitzky_golay,
        savitzky_golay_window=11,
        savitzky_golay_order=2,
        niterations_derivative=10,
        niterations_integration=5,
        verbose=false
    )
)

println("\n" * "="^80)
println("Method Comparison for simpleLin1:")
println("="^80)
println("Finite Differences:")
println("  Success: ", result_fd["success"])
println("  Time: ", @sprintf("%.2f", result_fd["discovery_time"]), "s")
println("  Integration loss: ", @sprintf("%.6e", result_fd["integration_loss"]))

println("\nSavitzky-Golay:")
println("  Success: ", result_sg["success"])
println("  Time: ", @sprintf("%.2f", result_sg["discovery_time"]), "s")
println("  Integration loss: ", @sprintf("%.6e", result_sg["integration_loss"]))

# Example 4: Benchmark all S-System problems (commented out - takes longer)
# println("\n\n" * "="^80)
# println("EXAMPLE 4: Benchmark All S-System Problems")
# println("="^80)
#
# results_ssystem = benchmark_all_problems(
#     problem_filter = name -> startswith(name, "ss_"),
#     ode_options = ODERegressionOptions(
#         niterations_derivative=15,
#         niterations_integration=8,
#         complexity_derivative=15,
#         complexity_integration=12,
#         differentiation_method=:savitzky_golay,
#         verbose=false
#     ),
#     save_results=true
# )

println("\n" * "="^80)
println("Benchmark Complete!")
println("="^80)
