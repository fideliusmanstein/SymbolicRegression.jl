"""
SymbolicRegressionODE.jl

Symbolic regression for discovering differential equations from time-series data.

This module implements a two-stage approach:
1. Derivative Estimation: Use symbolic regression to find dx/dt from numerical derivatives
2. Integration Refinement: Refine equations by solving ODEs and comparing integrated solutions

Compatible with benchmark problems from benchmarkProblems/BenchmarkSystems.jl
"""

module SymbolicRegressionODE

using DifferentialEquations
using SymbolicRegression
using Interpolations
using Logging
using SavitzkyGolay

export ODERegressionOptions, discover_ode_system, IntegrationLoss, create_feature_matrix

"""
    ODERegressionOptions

Configuration for ODE discovery through symbolic regression.

# Fields
- `binary_operators`: Binary operators for symbolic expressions (default: +, *, -, /)
- `unary_operators`: Unary operators for symbolic expressions (default: cos, sin, exp)
- `maxsize`: Maximum complexity of expressions (default: 20)
- `niterations_derivative`: Iterations for derivative search (default: 10)
- `niterations_integration`: Iterations for integration refinement (default: 5)
- `complexity_derivative`: Max complexity for derivative search (default: 15)
- `complexity_integration`: Max complexity for integration search (default: 10)
- `parallelism`: Parallelism mode (:serial, :multithreading, :multiprocessing)
- `differentiation_method`: Method for numerical derivatives (:finite_difference or :savitzky_golay)
- `savitzky_golay_window`: Window size for Savitzky-Golay filter (default: 11)
- `savitzky_golay_order`: Polynomial order for Savitzky-Golay filter (default: 2)
- `seed`: Random seed for reproducibility
- `verbose`: Enable verbose output
"""
struct ODERegressionOptions
    binary_operators::Tuple
    unary_operators::Tuple
    maxsize::Int
    niterations_derivative::Int
    niterations_integration::Int
    complexity_derivative::Int
    complexity_integration::Int
    parallelism::Symbol
    differentiation_method::Symbol
    savitzky_golay_window::Int
    savitzky_golay_order::Int
    seed::Int
    verbose::Bool
    
    function ODERegressionOptions(;
        binary_operators=(+, *, -, /),
        unary_operators=(cos, sin, exp),
        maxsize=20,
        niterations_derivative=10,
        niterations_integration=5,
        complexity_derivative=15,
        complexity_integration=10,
        parallelism=:multithreading,
        differentiation_method=:finite_difference,
        savitzky_golay_window=11,
        savitzky_golay_order=2,
        seed=42,
        verbose=true
    )
        @assert differentiation_method in [:finite_difference, :savitzky_golay] "differentiation_method must be :finite_difference or :savitzky_golay"
        @assert isodd(savitzky_golay_window) && savitzky_golay_window >= 3 "savitzky_golay_window must be odd and >= 3"
        @assert savitzky_golay_order >= 1 "savitzky_golay_order must be >= 1"
        new(binary_operators, unary_operators, maxsize, 
            niterations_derivative, niterations_integration,
            complexity_derivative, complexity_integration,
            parallelism, differentiation_method, savitzky_golay_window, 
            savitzky_golay_order, seed, verbose)
    end
end

"""
    compute_numerical_derivatives(t::Vector, X::Matrix; method=:finite_difference, 
                                 window=11, poly_order=2)

Compute numerical derivatives of state variables.

# Arguments
- `t`: Time vector (length n_time)
- `X`: State matrix (n_time × n_states)
- `method`: Derivative computation method (:finite_difference or :savitzky_golay)
- `window`: Window size for Savitzky-Golay filter (must be odd, default: 11)
- `poly_order`: Polynomial order for Savitzky-Golay filter (default: 2)

# Returns
- `dX`: Derivative matrix (n_time × n_states)
"""
function compute_numerical_derivatives(t::Vector, X::Matrix; 
                                      method=:finite_difference,
                                      window=11, 
                                      poly_order=2)
    n_time, n_states = size(X)
    dX = zeros(n_time, n_states)
    
    for i in 1:n_states
        if method == :finite_difference
            # Central difference for interior points
            for j in 2:n_time-1
                dX[j, i] = (X[j+1, i] - X[j-1, i]) / (t[j+1] - t[j-1])
            end
            # Forward/backward difference for endpoints
            dX[1, i] = (X[2, i] - X[1, i]) / (t[2] - t[1])
            dX[end, i] = (X[end, i] - X[end-1, i]) / (t[end] - t[end-1])
        elseif method == :savitzky_golay
            # Savitzky-Golay filter for smoothed derivatives
            h = Float64(t[2] - t[1])  # Assume uniform spacing
            deriv_raw = savitzky_golay(X[:, i], window, poly_order, deriv=1)
            dX[:, i] = deriv_raw.y ./ h
        else
            error("Unknown differentiation method: $method. Use :finite_difference or :savitzky_golay")
        end
    end
    
    return dX
end

"""
    create_feature_matrix(t::Vector, X::Matrix, inputs::Dict=Dict())

Create feature matrix for symbolic regression: [t, x1, x2, ..., u1, u2, ...]

# Arguments
- `t`: Time vector
- `X`: State matrix (n_time × n_states)
- `inputs`: Dictionary of input functions (optional)

# Returns
- Feature matrix (n_features × n_time) where features are [t; states; inputs]
"""
function create_feature_matrix(t::Vector, X::Matrix, inputs::Dict=Dict())
    n_time, n_states = size(X)
    
    # Start with time and states
    features = vcat(t', X')  # Shape: (1 + n_states) × n_time
    
    # Add inputs if provided
    if !isempty(inputs)
        input_keys = sort(collect(keys(inputs)))
        for key in input_keys
            input_func = inputs[key]
            input_values = [input_func(ti) for ti in t]
            features = vcat(features, input_values')
        end
    end
    
    return features
end

"""
    discover_derivatives(t, X, inputs, ode_options)

Stage 1: Discover derivative equations using symbolic regression on numerical derivatives.

# Arguments
- `t`: Time vector
- `X`: State matrix (n_time × n_states)
- `inputs`: Dictionary of input functions
- `ode_options`: ODERegressionOptions

# Returns
- Vector of PopMember vectors (one per state), each containing candidate equations
"""
function discover_derivatives(t::Vector, X::Matrix, inputs::Dict, ode_options::ODERegressionOptions)
    n_states = size(X, 2)
    
    # Compute numerical derivatives using specified method
    dX = compute_numerical_derivatives(t, X; 
        method=ode_options.differentiation_method,
        window=ode_options.savitzky_golay_window,
        poly_order=ode_options.savitzky_golay_order)
    
    # Create feature matrix [t; x1; x2; ...; u1; u2; ...]
    features = create_feature_matrix(t, X, inputs)
    
    if ode_options.verbose
        println("="^80)
        println("Stage 1: Discovering Derivative Equations")
        println("="^80)
        println("Number of states: ", n_states)
        println("Number of time points: ", length(t))
        println("Feature dimensions: ", size(features))
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
        
        # Target is derivative of state i
        target = dX[:, i]
        
        # Run symbolic regression
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

"""
    IntegrationLoss

Loss function that evaluates candidate ODE systems by integrating them
and comparing to observed trajectories.
"""
struct IntegrationLoss
    t::Vector{Float64}
    X_observed::Matrix{Float64}
    inputs::Dict
    
    function IntegrationLoss(t, X_observed, inputs=Dict())
        new(t, X_observed, inputs)
    end
end

"""
    evaluate_ode_system(trees, loss_config)

Evaluate a candidate ODE system by integrating and comparing to data.

# Arguments
- `trees`: Vector of expression trees, one per state (dx_i/dt = trees[i])
- `loss_config`: IntegrationLoss configuration

# Returns
- Loss value (mean squared error between integrated and observed trajectories)
"""
function evaluate_ode_system(trees::Vector, loss_config::IntegrationLoss)
    n_states = length(trees)
    n_time = length(loss_config.t)
    
    # Initial conditions from first time point
    x0 = loss_config.X_observed[1, :]
    tspan = (loss_config.t[1], loss_config.t[end])
    
    # Create input interpolators if inputs exist
    input_interps = Dict()
    if !isempty(loss_config.inputs)
        for (key, func) in loss_config.inputs
            input_values = [func(t) for t in loss_config.t]
            input_interps[key] = LinearInterpolation(loss_config.t, input_values)
        end
    end
    
    # Define ODE system dynamics
    function ode_dynamics!(dx, x, p, t_curr)
        # Check for invalid states
        if !all(isfinite, x) || !isfinite(t_curr)
            fill!(dx, Inf)
            return
        end
        
        # Build feature vector [t; x1; x2; ...; u1; u2; ...]
        features = vcat([t_curr], x)
        
        # Add interpolated inputs
        if !isempty(input_interps)
            input_keys = sort(collect(keys(input_interps)))
            for key in input_keys
                push!(features, input_interps[key](t_curr))
            end
        end
        
        # Reshape for tree evaluation
        feature_matrix = reshape(features, :, 1)
        
        # Evaluate each tree to get derivatives
        try
            for i in 1:n_states
                dx[i] = trees[i](feature_matrix)[1]
            end
            
            # Check for valid outputs
            if !all(isfinite, dx)
                fill!(dx, Inf)
            end
        catch
            fill!(dx, Inf)
        end
    end
    
    # Solve ODE system
    try
        prob = ODEProblem(ode_dynamics!, x0, tspan)
        sol = solve(
            prob,
            AutoTsit5(Rosenbrock23()),
            saveat=loss_config.t,
            maxiters=5000,
            abstol=1e-3,
            reltol=1e-3
        )
        
        # Check if solution succeeded and has correct length
        if SciMLBase.successful_retcode(sol) && length(sol.u) == n_time
            # Convert solution to matrix
            X_predicted = hcat([sol.u[i] for i in 1:length(sol.u)]...)'
            
            # Check all predictions are finite
            if all(isfinite, X_predicted)
                # Mean squared error
                return sum((X_predicted .- loss_config.X_observed).^2) / length(X_predicted)
            end
        end
    catch e
        # Integration failed
    end
    
    return Inf
end

"""
    refine_with_integration(derivative_candidates, t, X, inputs, ode_options)

Stage 2: Refine equations by testing combinations with integration-based loss.

# Arguments
- `derivative_candidates`: Vector of candidate equations per state
- `t`: Time vector
- `X`: State matrix
- `inputs`: Input functions dictionary
- `ode_options`: ODERegressionOptions

# Returns
- Tuple of (best_trees, best_loss, best_indices)
"""
function refine_with_integration(
    derivative_candidates::Vector{Vector},
    t::Vector,
    X::Matrix,
    inputs::Dict,
    ode_options::ODERegressionOptions
)
    n_states = length(derivative_candidates)
    
    if ode_options.verbose
        println("\n" * "="^80)
        println("Stage 2: Integration-Based Refinement")
        println("="^80)
    end
    
    # Filter candidates by complexity
    filtered_candidates = Vector{Vector}(undef, n_states)
    sr_options = SymbolicRegression.Options(;
        binary_operators=ode_options.binary_operators,
        unary_operators=ode_options.unary_operators,
        maxsize=ode_options.complexity_integration
    )
    
    for i in 1:n_states
        filtered = filter(derivative_candidates[i]) do member
            compute_complexity(member, sr_options) <= ode_options.complexity_integration
        end
        filtered_candidates[i] = filtered
    end
    
    candidates_per_state = [length(fc) for fc in filtered_candidates]
    total_combinations = prod(candidates_per_state)
    
    if ode_options.verbose
        println("Candidates per state (complexity ≤ $(ode_options.complexity_integration)): ", candidates_per_state)
        println("Total combinations to test: ", total_combinations)
        println()
    end
    
    # Create loss configuration
    loss_config = IntegrationLoss(t, X, inputs)
    
    # Search for best combination
    best_loss = Inf
    best_trees = nothing
    best_indices = nothing
    combinations_tested = 0
    
    # Recursive combination search
    function test_combinations(state_idx::Int, current_trees::Vector, current_indices::Vector{Int})
        if state_idx > n_states
            # Evaluate this combination
            combinations_tested += 1
            
            # Progress indicator
            if ode_options.verbose && combinations_tested % max(1, div(total_combinations, 10)) == 0
                progress_pct = round(100 * combinations_tested / total_combinations, digits=1)
                println("Progress: $combinations_tested/$total_combinations ($progress_pct%)")
            end
            
            loss = evaluate_ode_system(current_trees, loss_config)
            
            if loss < best_loss
                best_loss = loss
                best_trees = copy(current_trees)
                best_indices = copy(current_indices)
            end
            return
        end
        
        # Try each candidate for current state
        for (i, candidate) in enumerate(filtered_candidates[state_idx])
            test_combinations(
                state_idx + 1,
                [current_trees; candidate.tree],
                [current_indices; i]
            )
        end
    end
    
    # Start search
    test_combinations(1, [], Int[])
    
    # Display results
    if ode_options.verbose
        println("\n" * "="^80)
        println("Best ODE System Found")
        println("="^80)
        
        for (i, (tree, idx)) in enumerate(zip(best_trees, best_indices))
            member = filtered_candidates[i][idx]
            complexity = compute_complexity(member, sr_options)
            println("\nState $i (candidate $idx/$(candidates_per_state[i])):")
            println("  Derivative loss: ", round(member.loss, sigdigits=4))
            println("  Complexity: ", complexity)
            println("  dx$i/dt = ", string_tree(tree, sr_options))
        end
        
        println("\n" * "="^80)
        println("Integration loss: ", round(best_loss, sigdigits=4))
        println("="^80)
    end
    
    return best_trees, best_loss, best_indices
end

"""
    discover_ode_system(experiments; ode_options=ODERegressionOptions())

Main function: Discover ODE system from experimental time-series data.

# Arguments
- `experiments`: Vector of experiment dictionaries from benchmark problems.
                 Each experiment should have keys: `:t`, `:X`, `:inputs`
- `ode_options`: Configuration options (default: ODERegressionOptions())

# Returns
- Named tuple with:
  - `derivative_candidates`: All candidates from Stage 1
  - `best_trees`: Best equation trees from Stage 2
  - `integration_loss`: Integration-based loss
  - `best_indices`: Indices of selected candidates

# Example
```julia
include("benchmarkProblems/BenchmarkSystems.jl")
using .BenchmarkSystems

# Load a benchmark problem
experiments = BenchmarkSystems.load_problem("simpleLin1")

# Discover ODE system
result = discover_ode_system(experiments)

# Access results
println("Best equations: ", result.best_trees)
println("Integration loss: ", result.integration_loss)
```
"""
function discover_ode_system(
    experiments::Vector;
    ode_options::ODERegressionOptions = ODERegressionOptions()
)
    # Use first experiment for ODE discovery
    # (In practice, you might want to combine multiple experiments)
    exp = experiments[1]
    
    t = exp[:t]
    X_raw = exp[:X]
    # Ensure X is a Matrix (not Adjoint or other type)
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
    
    # Stage 1: Discover derivatives from numerical differentiation
    derivative_candidates = discover_derivatives(t, X, inputs, ode_options)
    
    # Stage 2: Refine with integration-based loss
    best_trees, integration_loss, best_indices = refine_with_integration(
        derivative_candidates, t, X, inputs, ode_options
    )
    
    return (
        derivative_candidates = derivative_candidates,
        best_trees = best_trees,
        integration_loss = integration_loss,
        best_indices = best_indices
    )
end

end # module
