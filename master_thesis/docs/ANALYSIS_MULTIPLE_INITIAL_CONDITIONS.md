# Analysis: Multi-Trajectory Dataset Enhancement

## Problem Statement

Currently, the symbolic regression ODE discovery system evaluates candidates on a **single trajectory** (one run with a single initial condition). This allows incorrect solutions to achieve good integration loss if they happen to fit that particular trajectory well, even though they may not be the true underlying equations.

**Goal**: Add capability to generate and evaluate against **multiple different trajectories** from the same ODE system with different initial conditions, ensuring candidates must fit all trajectories to be considered correct.

---

## Current Architecture

### Data Generation Pipeline
```
BenchmarkSystems.jl
├── Benchmark Problem Modules
│   └── Each problem's generate_*_data() function
│       └── Returns: (t, X, inputs) - single trajectory
├── load_problem(name)
│   └── Returns: experiments = [Dict(:t => t, :X => X, :inputs => inputs)]
│       └── Vector with single Dict per problem
```

### Evaluation Pipeline
```
discover_ode_system(experiments)
├── Stage 1: discover_derivatives()
│   ├── Extract first experiment: exp = experiments[1]
│   ├── Compute numerical derivatives from X
│   ├── Create feature matrix [t; states; inputs]
│   └── Symbolic regression on each state variable
├── Stage 2: refine_with_integration()
│   ├── Filter candidates by complexity
│   ├── Test all combinations
│   ├── evaluate_ode_system(trees, loss_config)
│   │   ├── IntegrationLoss contains: (t, X_observed, inputs)
│   │   ├── Integrate from X_observed[1, :] (initial condition)
│   │   └── Compare integrated X_predicted to X_observed
│   │   └── Return MSE loss
│   └── Select combination with minimum loss
```

### Key Functions & Data Structures

**IntegrationLoss struct** (line 264-270):
```julia
struct IntegrationLoss
    t::Vector{Float64}
    X_observed::Matrix{Float64}
    inputs::Dict
end
```
- Currently holds data for **ONE trajectory only**

**evaluate_ode_system()** (line 274-355):
```julia
function evaluate_ode_system(trees::Vector, loss_config::IntegrationLoss)
    # Integrates ODEs from initial condition
    # Returns MSE against X_observed (single trajectory)
end
```

**discover_ode_system()** (line 525-566):
```julia
function discover_ode_system(experiments::Vector; ode_options)
    exp = experiments[1]  # ← ONLY USES FIRST EXPERIMENT
    ...
    derivative_candidates = discover_derivatives(t, X, inputs, ode_options)
    ...
end
```

---

## Required Changes

### 1. **Data Generation Layer** - Minor Changes

**Current**: `generate_*_data()` returns one trajectory
**Change**: Generate multiple trajectories by varying initial conditions

**Files affected**:
- `benchmarkProblems/ChemicalRateProblems/*.jl`
- `benchmarkProblems/SSystemProblems/*.jl`
- `benchmarkProblems/GMAProblems/*.jl`
- `benchmarkProblems/RealBiologicalProblems/*.jl`

**Implementation approach**:
```julia
# Current (example from simpleLin.jl):
function generate_simplelin_experiments(; num_trajectories=1, ...)
    experiments = []
    for ic_idx in 1:num_trajectories
        # Vary initial conditions (scaled factors, random, or grid)
        X3_0_scaled = X3_0 * (0.5 + ic_idx * 0.2)
        X4_0_scaled = X4_0 * (0.5 + ic_idx * 0.2)
        ...
        t, X, inputs = generate_simplelin_data(
            X3_0=X3_0_scaled, X4_0=X4_0_scaled, ...
        )
        push!(experiments, Dict(:t => t, :X => X, :inputs => inputs))
    end
    return experiments
end
```

**Impact**: Minimal - just loops over existing single-trajectory generation

### 2. **Feature Extraction Layer** - MAJOR Changes

**Stage 1 Problem**: Numerical derivatives computed per trajectory
- Currently: `compute_numerical_derivatives(t, X)` → derivatives for ONE trajectory
- **Need**: Combine derivatives across all trajectories

**Current flow**:
```
discover_derivatives(t, X, inputs, options)
    ├── dX = compute_numerical_derivatives(t, X)  # Single trajectory
    ├── features = create_feature_matrix(t, X, inputs)  # One trajectory
    └── For each state: symbolic_regression(features, dX[:, i])
```

**Change approach**:
```
discover_derivatives(experiments, inputs, options)  # Now takes ALL experiments
    ├── For each state i:
    │   ├── Collect all dX_i from all trajectories
    │   ├── Collect all features from all trajectories  
    │   ├── Concatenate: dX_combined, features_combined
    │   └── symbolic_regression(features_combined, dX_combined)
    └── This ensures equations fit derivatives across ALL trajectories
```

**Functions to modify**:
1. `discover_derivatives(experiments::Vector, inputs, options)` instead of `(t, X, inputs, options)`
2. `compute_numerical_derivatives()` - stays the same (per-trajectory)
3. `create_feature_matrix()` - stays the same but called multiple times
4. Add new function: `aggregate_features_derivatives(experiments)` to combine across trajectories

### 3. **Integration Evaluation Layer** - CRITICAL Changes

**Stage 2 Problem**: Loss evaluated on single trajectory
- Currently: `evaluate_ode_system(trees, loss_config::IntegrationLoss)` 
- Evaluates one ODE integration against one trajectory
- **Need**: Evaluate against ALL trajectories and sum/average errors

**Change IntegrationLoss struct**:
```julia
struct IntegrationLoss
    trajectories::Vector{Dict}  # Each has (:t, :X_observed, :inputs)
    # OR keep separate arrays:
    t_list::Vector{Vector}           # List of time vectors
    X_observed_list::Vector{Matrix}  # List of state matrices
    inputs_list::Vector{Dict}        # List of input dicts
end
```

**Change evaluate_ode_system()**:
```julia
function evaluate_ode_system(trees::Vector, loss_config::IntegrationLoss)
    total_loss = 0.0
    n_trajectories = length(loss_config.trajectories)
    
    for traj_idx in 1:n_trajectories
        # Extract this trajectory
        t = loss_config.trajectories[traj_idx][:t]
        X_obs = loss_config.trajectories[traj_idx][:X_observed]
        inputs = loss_config.trajectories[traj_idx][:inputs]
        
        # Integrate from THIS trajectory's initial condition
        x0 = X_obs[1, :]
        tspan = (t[1], t[end])
        
        # ... integrate ODE ...
        
        # Compute MSE for this trajectory
        loss_traj = mean((X_predicted .- X_obs).^2)
        
        # Accumulate
        total_loss += loss_traj
    end
    
    # Average or weighted average
    return total_loss / n_trajectories
end
```

**Impact**: Critical - fundamentally changes error evaluation

### 4. **Main Discovery Function** - Major Changes

**Change discover_ode_system()**:
```julia
function discover_ode_system(experiments::Vector; ode_options)
    # Previously took experiments but only used [1]
    
    if ode_options.verbose
        println("Discovered $(length(experiments)) trajectories")
    end
    
    # Stage 1: Now learns from all trajectories
    derivative_candidates = discover_derivatives(
        experiments,  # All trajectories
        get(experiments[1], :inputs, Dict()),
        ode_options
    )
    
    # Stage 2: Now evaluates against all trajectories  
    best_trees, integration_loss, best_indices = refine_with_integration(
        derivative_candidates,
        experiments,  # Pass all trajectories
        ode_options
    )
    
    return (...)
end
```

### 5. **Integration Refinement Function** - Major Changes

**Change refine_with_integration()**:
```julia
function refine_with_integration(
    derivative_candidates::Vector{Vector},
    experiments::Vector,  # Changed from (t, X, inputs)
    ode_options::ODERegressionOptions
)
    # Create loss config from ALL trajectories
    loss_config = IntegrationLoss(experiments)
    
    # Rest of logic remains same, but evaluate_ode_system() now
    # automatically handles all trajectories
    ...
end
```

---

## Summary of File Changes

| File | Function(s) | Changes |
|------|-------------|---------|
| **SymbolicRegressionODE.jl** | **discover_derivatives()** | Change signature: take `experiments` not `(t, X, inputs)` |
| | **refine_with_integration()** | Change to accept `experiments` vector; modify loss config creation |
| | **evaluate_ode_system()** | Iterate over multiple trajectories in loss config; aggregate losses |
| | **discover_ode_system()** | Pass all experiments to both stages |
| | **IntegrationLoss** | Restructure to hold multiple trajectories |
| | **compute_feature_matrix()** | Add overload for multiple trajectories OR let caller concatenate |
| **BenchmarkSystems.jl** | **load_problem()** | Optionally accept `num_trajectories` parameter |
| **ChemicalRateProblems/*.jl** | **generate_*_experiments()** | NEW: Accept parameter for number of ICs |
| **SSystemProblems/*.jl** | Similar | NEW: Multiple trajectory generation |
| **example_ode_discovery.jl** | Examples | Update to pass `num_trajectories` parameter |
| **benchmark_ode_discovery.jl** | **benchmark_single_problem()** | Accept and pass through `num_trajectories` |

---

## Implementation Priority

### Phase 1: Infrastructure (Minimal Risk)
1. Update `load_problem()` to accept `num_trajectories` parameter
2. Modify benchmark problem modules to generate multiple trajectories
3. Ensure experiments vector structure is correct

### Phase 2: Core Logic (High Impact)
1. Modify `IntegrationLoss` struct
2. Update `evaluate_ode_system()` to handle multiple trajectories
3. Update `refine_with_integration()` signature
4. Update `discover_ode_system()` to use all experiments

### Phase 3: Feature Aggregation (Quality Improvement)  
1. Modify `discover_derivatives()` to combine features/derivatives
2. Add `aggregate_features_derivatives()` helper
3. Test that Stage 1 learns better with more data

### Phase 4: Testing & Validation
1. Update examples to use multiple trajectories
2. Add tests comparing single vs. multiple trajectory performance
3. Verify incorrect solutions are now rejected

---

## Potential Challenges

1. **Derivative Computation Complexity**: Combining derivatives from different initial conditions increases feature matrix size. Need to verify this doesn't:
   - Explode dimensionality  
   - Cause overfitting in Stage 1
   - Slow down significantly

2. **Different Time Spans**: If trajectories have different time points, need interpolation strategy

3. **Input Consistency**: If inputs vary between trajectories, must ensure proper handling

4. **Combination Explosion**: Stage 2 already tests many combinations. More trajectories may increase computation.

5. **Backward Compatibility**: Need to ensure existing code still works with single trajectory

---

## Expected Benefits

✅ **Improved Robustness**: Equations must fit multiple initial conditions  
✅ **Prevents Overfitting**: Can't exploit quirks of single trajectory  
✅ **Better Generalization**: Discovered equations more likely to be true system equations  
✅ **Better ODE Solver Feedback**: Stage 2 integrates from different x0 values  
✅ **Higher Sensitivity**: Wrong equations fail on at least one trajectory

