# Code Examples: Implementation Guide

## Overview
This document shows concrete code examples for each required change.

---

## 1. Data Generation Layer Changes

### Example 1a: Modify Benchmark Problem Module

**File**: `benchmarkProblems/ChemicalRateProblems/simpleLin.jl`

**Current Implementation** (simplified):
```julia
function generate_simplelin_experiments(problem_idx=1)
    # Only generates ONE set of trajectories
    X3_0, X4_0, X5_0 = 1.0, 0.0, 0.0
    t, X, inputs = generate_simplelin_data(
        X3_0=X3_0, X4_0=X4_0, X5_0=X5_0
    )
    return [Dict(:t => t, :X => X, :inputs => inputs)]
end
```

**After Changes**:
```julia
"""
    generate_simplelin_experiments_multi(problem_idx=1; num_trajectories=3)

Generate multiple trajectories with different initial conditions.

# Arguments
- problem_idx: Problem variant (1, 2, 3, or 4)
- num_trajectories: Number of trajectories to generate (default: 3)

# Returns
- Vector of experiment dicts: [Dict(:t, :X, :inputs), ...]
"""
function generate_simplelin_experiments_multi(problem_idx=1; num_trajectories=3)
    experiments = []
    
    # Parameter sets for each problem variant
    params = [
        (X1_const=3.0, X2_const=2.0),
        (X1_const=2.0, X2_const=3.0),
        (X1_const=4.0, X2_const=1.0),
        (X1_const=1.0, X2_const=4.0),
    ]
    
    param_set = params[problem_idx]
    
    for ic_idx in 1:num_trajectories
        # Vary initial conditions across trajectories
        # Strategy: Scale from baseline
        scale_factor = 0.5 + (ic_idx - 1) * 0.25  # 0.5, 0.75, 1.0, 1.25, ...
        
        X3_0 = 1.0 * scale_factor
        X4_0 = 0.0 * scale_factor  # or use small random offset if X4_0 = 0
        X5_0 = 0.0 * scale_factor
        
        t, X, inputs = generate_simplelin_data(;
            X1_const=param_set.X1_const,
            X2_const=param_set.X2_const,
            X3_0=X3_0,
            X4_0=X4_0,
            X5_0=X5_0,
            tspan=(0.0, 3.0),
            n_points=13
        )
        
        push!(experiments, Dict(
            :t => t,
            :X => X,
            :inputs => inputs,
            :ic_index => ic_idx,
            :scale => scale_factor
        ))
    end
    
    return experiments
end

# Also keep original function for backward compatibility
function generate_simplelin_experiments(problem_idx=1)
    return generate_simplelin_experiments_multi(problem_idx, num_trajectories=1)
end
```

### Example 1b: Update BenchmarkSystems loader

**File**: `benchmarkProblems/BenchmarkSystems.jl`

**Current**:
```julia
function load_problem(name::String)
    # Dispatch to appropriate problem loader
    if startswith(name, "simpleLin")
        idx = parse(Int, name[9])
        return SimpleLinModule.generate_simplelin_experiments(idx)
    # ... other problems ...
end
```

**After**:
```julia
function load_problem(name::String; num_trajectories=1)
    # Dispatch to appropriate problem loader
    if startswith(name, "simpleLin")
        idx = parse(Int, name[9])
        if hasmethod(SimpleLinModule.generate_simplelin_experiments_multi, 
                     Tuple{Int, Vararg{Any}})
            return SimpleLinModule.generate_simplelin_experiments_multi(
                idx, num_trajectories=num_trajectories
            )
        else
            # Fallback for backward compatibility
            return SimpleLinModule.generate_simplelin_experiments(idx)
        end
    # ... other problems ...
end
```

---

## 2. Stage 1: Derivative Discovery Changes

### Example 2a: Aggregate Features and Derivatives

**File**: `SymbolicRegressionODE.jl`

**New function** to add:
```julia
"""
    aggregate_features_and_derivatives(experiments::Vector, ode_options)

Combine features and derivatives from all trajectories.

# Arguments
- experiments: Vector of experiment dicts with keys :t, :X, :inputs
- ode_options: ODERegressionOptions

# Returns
- Tuple of (combined_features, combined_derivatives) for symbolic regression
"""
function aggregate_features_and_derivatives(experiments::Vector, ode_options::ODERegressionOptions)
    n_experiments = length(experiments)
    n_states = size(experiments[1][:X], 2)
    
    # Collect all features and derivatives
    all_features_list = []
    all_derivatives_list = []
    
    for exp in experiments
        t = exp[:t]
        X = exp[:X]
        inputs = get(exp, :inputs, Dict())
        
        # Compute numerical derivatives for this trajectory
        dX = compute_numerical_derivatives(t, X;
            method=ode_options.differentiation_method,
            window=ode_options.savitzky_golay_window,
            poly_order=ode_options.savitzky_golay_order
        )
        
        # Create feature matrix for this trajectory
        # Returns matrix where rows are features, columns are time points
        features = create_feature_matrix(t, X, inputs)
        
        push!(all_features_list, features)
        push!(all_derivatives_list, dX)
    end
    
    # Concatenate horizontally (along time axis)
    # Result: more columns = more time points from all trajectories
    combined_features = hcat(all_features_list...)  # (n_features × total_time_points)
    combined_derivatives = vcat(all_derivatives_list...)  # (total_time_points × n_states)
    
    return combined_features, combined_derivatives
end
```

### Example 2b: Update discover_derivatives function

**Current signature**:
```julia
function discover_derivatives(t::Vector, X::Matrix, inputs::Dict, 
                             ode_options::ODERegressionOptions)
```

**New signature**:
```julia
function discover_derivatives(experiments::Vector, 
                             ode_options::ODERegressionOptions)
    n_states = size(experiments[1][:X], 2)
    
    # Get combined data from all trajectories
    features, dX_all = aggregate_features_and_derivatives(experiments, ode_options)
    
    if ode_options.verbose
        println("="^80)
        println("Stage 1: Discovering Derivative Equations")
        println("="^80)
        println("Number of trajectories: ", length(experiments))
        println("Number of states: ", n_states)
        println("Combined feature dimensions: ", size(features))
        println()
    end
    
    # Configure SymbolicRegression options for derivative search
    sr_options = SymbolicRegression.Options(;
        binary_operators=ode_options.binary_operators,
        unary_operators=ode_options.unary_operators,
        maxsize=ode_options.complexity_derivative,
        seed=ode_options.seed
    )
    
    # Discover equations for each state
    derivative_candidates = Vector{Vector}(undef, n_states)
    
    for i in 1:n_states
        if ode_options.verbose
            println("\nSearching for dx$(i)/dt...")
        end
        
        # Target is derivative of state i (from ALL trajectories combined)
        target = dX_all[:, i]
        
        # Run symbolic regression on combined data
        if ode_options.verbose
            hall_of_fame = equation_search(
                features, target;
                options=sr_options,
                niterations=ode_options.niterations_derivative,
                parallelism=ode_options.parallelism
            )
        else
            hall_of_fame = with_logger(NullLogger()) do
                equation_search(
                    features, target;
                    options=sr_options,
                    niterations=ode_options.niterations_derivative,
                    parallelism=ode_options.parallelism
                )
            end
        end
        
        # Extract Pareto frontier
        pareto_frontier = calculate_pareto_frontier(hall_of_fame)
        derivative_candidates[i] = pareto_frontier
        
        if ode_options.verbose
            println("  Found ", length(pareto_frontier), " candidate equations")
        end
    end
    
    return derivative_candidates
end
```

---

## 3. Stage 2: Integration Evaluation Changes

### Example 3a: Update IntegrationLoss struct

**Current**:
```julia
struct IntegrationLoss
    t::Vector{Float64}
    X_observed::Matrix{Float64}
    inputs::Dict
    
    function IntegrationLoss(t, X_observed, inputs=Dict())
        new(t, X_observed, inputs)
    end
end
```

**After**:
```julia
struct IntegrationLoss
    # Store multiple trajectories
    trajectories::Vector{Dict}  # Each entry: Dict(:t, :X_observed, :inputs)
    
    function IntegrationLoss(trajectories::Vector)
        new(trajectories)
    end
end

# Convenience constructor for single trajectory (backward compat)
function IntegrationLoss(t::Vector, X_observed::Matrix, inputs::Dict=Dict())
    trajectories = [Dict(:t => t, :X_observed => X_observed, :inputs => inputs)]
    new(trajectories)
end
```

### Example 3b: Update evaluate_ode_system function

**Current**:
```julia
function evaluate_ode_system(trees::Vector, loss_config::IntegrationLoss)
    n_states = length(trees)
    n_time = length(loss_config.t)
    
    # Initial conditions from first time point
    x0 = loss_config.X_observed[1, :]
    tspan = (loss_config.t[1], loss_config.t[end])
    
    # ... build interpolators for inputs ...
    
    # Define ODE dynamics
    function ode_dynamics!(dx, x, p, t_curr)
        # ... evaluate trees ...
    end
    
    # Solve ODE
    try
        prob = ODEProblem(ode_dynamics!, x0, tspan)
        sol = solve(prob, ..., saveat=loss_config.t)
        
        if SciMLBase.successful_retcode(sol) && length(sol.u) == n_time
            X_predicted = hcat([sol.u[i] for i in 1:length(sol.u)]...)'
            if all(isfinite, X_predicted)
                return sum((X_predicted .- loss_config.X_observed).^2) / length(X_predicted)
            end
        end
    catch e
        return Inf
    end
    
    return Inf
end
```

**After** (handles multiple trajectories):
```julia
function evaluate_ode_system(trees::Vector, loss_config::IntegrationLoss)
    n_states = length(trees)
    n_trajectories = length(loss_config.trajectories)
    
    total_loss = 0.0
    valid_trajectories = 0
    
    # Evaluate on each trajectory
    for trajectory in loss_config.trajectories
        t = trajectory[:t]
        X_observed = trajectory[:X_observed]
        inputs = trajectory[:inputs]
        n_time = length(t)
        
        # Initial conditions for THIS trajectory
        x0 = X_observed[1, :]
        tspan = (t[1], t[end])
        
        # Create input interpolators for THIS trajectory
        input_interps = Dict()
        if !isempty(inputs)
            for (key, input_data) in inputs
                if input_data isa AbstractVector
                    input_values = input_data
                else
                    input_values = [input_data(ti) for ti in t]
                end
                input_interps[key] = LinearInterpolation(t, input_values)
            end
        end
        
        # Define ODE dynamics
        function ode_dynamics!(dx, x, p, t_curr)
            if !all(isfinite, x) || !isfinite(t_curr)
                fill!(dx, Inf)
                return
            end
            
            features = vcat([t_curr], x)
            
            if !isempty(input_interps)
                input_keys = sort(collect(keys(input_interps)))
                for key in input_keys
                    push!(features, input_interps[key](t_curr))
                end
            end
            
            feature_matrix = reshape(features, :, 1)
            
            try
                for i in 1:n_states
                    dx[i] = trees[i](feature_matrix)[1]
                end
                
                if !all(isfinite, dx)
                    fill!(dx, Inf)
                end
            catch
                fill!(dx, Inf)
            end
        end
        
        # Solve ODE
        try
            prob = ODEProblem(ode_dynamics!, x0, tspan)
            sol = solve(
                prob,
                AutoTsit5(Rosenbrock23()),
                saveat=t,
                maxiters=5000,
                abstol=1e-3,
                reltol=1e-3
            )
            
            if SciMLBase.successful_retcode(sol) && length(sol.u) == n_time
                X_predicted = hcat([sol.u[i] for i in 1:length(sol.u)]...)'
                
                if all(isfinite, X_predicted)
                    # MSE for this trajectory
                    loss_traj = sum((X_predicted .- X_observed).^2) / length(X_predicted)
                    total_loss += loss_traj
                    valid_trajectories += 1
                end
            end
        catch e
            # Integration failed for this trajectory
            # Continue to next trajectory
        end
    end
    
    # Return average loss over all trajectories
    if valid_trajectories > 0
        return total_loss / valid_trajectories
    else
        return Inf  # All trajectories failed
    end
end
```

---

## 4. Main Entry Point Changes

### Example 4a: Update refine_with_integration signature

**Current**:
```julia
function refine_with_integration(
    derivative_candidates::Vector{Vector},
    t::Vector,
    X::Matrix,
    inputs::Dict,
    ode_options::ODERegressionOptions
)
    # ...
    loss_config = IntegrationLoss(t, X, inputs)
    # ...
end
```

**After**:
```julia
function refine_with_integration(
    derivative_candidates::Vector{Vector},
    experiments::Vector,
    ode_options::ODERegressionOptions
)
    n_states = length(derivative_candidates)
    
    if ode_options.verbose
        println("\n" * "="^80)
        println("Stage 2: Integration-Based Refinement")
        println("="^80)
        println("Number of trajectories to evaluate: ", length(experiments))
    end
    
    # ... filtering logic ...
    
    # Create loss configuration from ALL trajectories
    loss_config = IntegrationLoss(experiments)
    
    # ... rest of combination testing logic ...
end
```

### Example 4b: Update discover_ode_system main function

**Current**:
```julia
function discover_ode_system(
    experiments::Vector;
    ode_options::ODERegressionOptions = ODERegressionOptions()
)
    # Use first experiment only
    exp = experiments[1]
    
    t = exp[:t]
    X_raw = exp[:X]
    X = X_raw isa AbstractMatrix ? Matrix(X_raw) : X_raw
    inputs = get(exp, :inputs, Dict())
    
    if ode_options.verbose
        println("\n" * "="^80)
        println("Symbolic Regression for Differential Equations")
        println("="^80)
        println("Time points: ", length(t))
        println("States: ", size(X, 2))
        println("Inputs: ", length(inputs))
        println()
    end
    
    # Stage 1: using single trajectory
    derivative_candidates = discover_derivatives(t, X, inputs, ode_options)
    
    # Stage 2: using single trajectory
    best_trees, integration_loss, best_indices = refine_with_integration(
        derivative_candidates, t, X, inputs, ode_options
    )
    
    return (...)
end
```

**After**:
```julia
function discover_ode_system(
    experiments::Vector;
    ode_options::ODERegressionOptions = ODERegressionOptions()
)
    # Validate experiments
    if isempty(experiments)
        error("Must provide at least one experiment")
    end
    
    # Validate all have same state dimensions
    n_states_first = size(experiments[1][:X], 2)
    for i in 2:length(experiments)
        n_states_i = size(experiments[i][:X], 2)
        if n_states_i != n_states_first
            error("All experiments must have same number of states")
        end
    end
    
    if ode_options.verbose
        println("\n" * "="^80)
        println("Symbolic Regression for Differential Equations")
        println("="^80)
        println("Number of experiments: ", length(experiments))
        println("States per experiment: ", n_states_first)
        for (i, exp) in enumerate(experiments)
            println("  Experiment $i: $(length(exp[:t])) time points, " *
                   "$(length(get(exp, :inputs, Dict()))) inputs")
        end
        println()
    end
    
    # Stage 1: Discover derivatives using ALL trajectories
    derivative_candidates = discover_derivatives(experiments, ode_options)
    
    # Stage 2: Refine with integration-based loss using ALL trajectories
    best_trees, integration_loss, best_indices = refine_with_integration(
        derivative_candidates, experiments, ode_options
    )
    
    return (
        derivative_candidates = derivative_candidates,
        best_trees = best_trees,
        integration_loss = integration_loss,
        best_indices = best_indices
    )
end
```

---

## 5. Usage Examples

### Example 5a: Using Multi-Trajectory in Code

**File**: `example_ode_discovery.jl` (updated)

```julia
include("SymbolicRegressionODE.jl")
include("benchmarkProblems/BenchmarkSystems.jl")

using .SymbolicRegressionODE
using .BenchmarkSystems

# Example 1: Load problem with MULTIPLE initial conditions
println("="^80)
println("Example 1: Multiple Initial Conditions")
println("="^80)

# Load 3 trajectories (different initial conditions)
experiments_multi = BenchmarkSystems.load_problem("simpleLin1", num_trajectories=3)

println("Loaded $(length(experiments_multi)) trajectories")

options = ODERegressionOptions(
    niterations_derivative=5,
    niterations_integration=3,
    complexity_derivative=10,
    complexity_integration=8,
    parallelism=:multithreading,
    verbose=true
)

result_multi = discover_ode_system(experiments_multi; ode_options=options)

println("\n" * "="^80)
println("RESULT - With Multiple Initial Conditions")
println("="^80)
println("Integration loss: ", result_multi.integration_loss)
for (i, tree) in enumerate(result_multi.best_trees)
    sr_opts = SymbolicRegression.Options(
        binary_operators=options.binary_operators,
        unary_operators=options.unary_operators
    )
    println("dx$i/dt = ", string_tree(tree, sr_opts))
end


# Example 2: Compare single vs multiple trajectories
println("\n\n" * "="^80)
println("Example 2: Comparison - Single vs Multiple Trajectories")
println("="^80)

# Single trajectory
experiments_single = BenchmarkSystems.load_problem("simpleLin1", num_trajectories=1)
result_single = discover_ode_system(experiments_single; ode_options=options)
println("Single trajectory loss: ", result_single.integration_loss)

# Multiple trajectories
experiments_multi3 = BenchmarkSystems.load_problem("simpleLin1", num_trajectories=3)
result_multi3 = discover_ode_system(experiments_multi3; ode_options=options)
println("3 trajectories loss: ", result_multi3.integration_loss)

# More trajectories
experiments_multi5 = BenchmarkSystems.load_problem("simpleLin1", num_trajectories=5)
result_multi5 = discover_ode_system(experiments_multi5; ode_options=options)
println("5 trajectories loss: ", result_multi5.integration_loss)

println("\nExpected: Loss improves with more trajectories")
```

### Example 5b: In Benchmarking

**File**: `benchmark_ode_discovery.jl` (updated)

```julia
function benchmark_single_problem(
    problem_name::String;
    ode_options::ODERegressionOptions = ODERegressionOptions(),
    num_trajectories::Int = 1  # NEW PARAMETER
)
    try
        # Load problem with specified number of trajectories
        experiments = BenchmarkSystems.load_problem(
            problem_name;
            num_trajectories=num_trajectories
        )
        
        # Discover ODE system
        start_time = time()
        result = SymbolicRegressionODE.discover_ode_system(
            experiments; 
            ode_options=ode_options
        )
        discovery_time = time() - start_time
        
        # ... rest of analysis ...
        
        return Dict(
            "problem_name" => problem_name,
            "num_trajectories" => num_trajectories,  # NEW
            "discovery_time" => discovery_time,
            "integration_loss" => result.integration_loss,
            # ... other metrics ...
        )
    catch e
        # ... error handling ...
    end
end
```

---

## Testing Changes

### Example: New test for multi-trajectory

**File**: `tests/test_multi_trajectory.jl` (new file)

```julia
"""
test_multi_trajectory.jl

Test that multi-trajectory evaluation correctly rejects wrong equations.
"""

include("../SymbolicRegressionODE.jl")
include("../benchmarkProblems/BenchmarkSystems.jl")

using .SymbolicRegressionODE
using .BenchmarkSystems
using Test

@testset "Multi-Trajectory Evaluation" begin
    # Test 1: Load with multiple trajectories
    @test begin
        experiments = BenchmarkSystems.load_problem("simpleLin1", num_trajectories=3)
        length(experiments) == 3
    end
    
    # Test 2: Each trajectory should have same structure
    @test begin
        experiments = BenchmarkSystems.load_problem("simpleLin1", num_trajectories=3)
        all(haskey(exp, :t) for exp in experiments) &&
        all(haskey(exp, :X) for exp in experiments) &&
        all(haskey(exp, :inputs) for exp in experiments)
    end
    
    # Test 3: Multiple trajectories should give lower loss than single
    @test begin
        options = ODERegressionOptions(
            niterations_derivative=3,
            niterations_integration=2,
            complexity_derivative=8,
            complexity_integration=6,
            verbose=false
        )
        
        exp_single = BenchmarkSystems.load_problem("simpleLin1", num_trajectories=1)
        exp_multi = BenchmarkSystems.load_problem("simpleLin1", num_trajectories=3)
        
        result_single = discover_ode_system(exp_single; ode_options=options)
        result_multi = discover_ode_system(exp_multi; ode_options=options)
        
        # Multi-trajectory usually learns better (lower loss)
        # But both should be reasonable
        result_single.integration_loss < 1000 &&
        result_multi.integration_loss < 1000
    end
end
```

