# Key Changes Summary: Multi-Trajectory Evaluation

## The Problem
- **Current behavior**: System evaluates candidates using ONE trajectory (single initial condition)
- **Issue**: Incorrect equations can achieve good results if they happen to fit that specific trajectory
- **Solution**: Generate multiple trajectories with different initial conditions and evaluate candidates against ALL of them

---

## What Needs to Change (Quick Reference)

### 1. Data Generation (10% effort)
**Where**: `benchmarkProblems/` modules  
**What**: Modify `generate_*_experiments()` to create multiple trajectories  
**How**: Loop over initial conditions with variations instead of just one

```julia
# Before: returns 1 trajectory
experiments = [Dict(:t => t, :X => X, :inputs => inputs)]

# After: returns N trajectories  
experiments = [
    Dict(:t => t1, :X => X1, :inputs => inputs),
    Dict(:t => t2, :X => X2, :inputs => inputs),
    Dict(:t => t3, :X => X3, :inputs => inputs),
]
```

### 2. Stage 1: Derivative Discovery (30% effort)
**Where**: `SymbolicRegressionODE.jl` - `discover_derivatives()`  
**Current**: Takes single `(t, X, inputs)` and computes derivatives for that trajectory  
**Change**: Take ALL experiments and aggregate their derivatives/features

```julia
# Before:
discover_derivatives(t, X, inputs, ode_options)

# After:  
discover_derivatives(experiments::Vector, ode_options)
    # Concatenate features and derivatives from all trajectories
    # Then run symbolic regression on combined data
```

**Why**: More data points = better derivative fitting = less noise sensitivity

### 3. Stage 2: Integration Evaluation (60% effort) - **MOST CRITICAL**
**Where**: `SymbolicRegressionODE.jl` - `evaluate_ode_system()` and `IntegrationLoss`  
**Current**: Evaluates ODE integration against ONE observed trajectory  
**Change**: Evaluate against ALL trajectories and sum/average the errors

```julia
# Before:
struct IntegrationLoss
    t::Vector{Float64}
    X_observed::Matrix{Float64}  # Single trajectory
    inputs::Dict
end

# After:
struct IntegrationLoss
    trajectories::Vector{Dict}   # Multiple trajectories
end

# Before:
function evaluate_ode_system(trees, loss_config)
    # Integrate once, compare to single X_observed
    loss = mean((X_predicted - X_observed)^2)
    return loss
end

# After:
function evaluate_ode_system(trees, loss_config)
    total_loss = 0.0
    for trajectory in loss_config.trajectories
        # Integrate from THIS trajectory's initial condition
        loss_i = mean((X_predicted_i - trajectory[:X])^2)
        total_loss += loss_i
    end
    return total_loss / length(trajectories)
end
```

**Why**: This is where incorrect equations get filtered out. If an equation only works for one IC, it will fail here.

### 4. Main Entry Point (5% effort)
**Where**: `SymbolicRegressionODE.jl` - `discover_ode_system()`  
**Current**: Only uses `experiments[1]`  
**Change**: Pass entire `experiments` vector to both stages

```julia
# Before:
exp = experiments[1]
derivative_candidates = discover_derivatives(exp[:t], exp[:X], exp[:inputs], ...)

# After:
derivative_candidates = discover_derivatives(experiments, ...)
```

---

## Architecture Diagram: Before vs After

### BEFORE: Single Trajectory
```
experiments = [
    {t: [...], X: [...], inputs: {...}}  ← Only this used
]
        ↓
discover_ode_system()
    ├─ Stage 1: Find derivatives from one trajectory
    │  └─ Features: 150 points
    │  └─ Each feature vector: [t, x1, x2, x3, u1, u2]
    │
    └─ Stage 2: Evaluate candidate equations
       ├─ Test each combination
       ├─ Integrate ODE from X[0]
       └─ Compare to 150 data points  ← Only one trajectory
           └─ RESULT: Good fit ≠ True equation (could be wrong)
```

### AFTER: Multiple Trajectories  
```
experiments = [
    {t: [...], X: [...], inputs: {...}},  ← IC: x0=1.0
    {t: [...], X: [...], inputs: {...}},  ← IC: x0=2.0
    {t: [...], X: [...], inputs: {...}},  ← IC: x0=3.0
]
        ↓
discover_ode_system()
    ├─ Stage 1: Find derivatives from ALL trajectories
    │  └─ Features: 150×3 = 450 points (combined)
    │  └─ More data = less noise, better fits
    │
    └─ Stage 2: Evaluate candidate equations
       ├─ Test each combination
       ├─ For each trajectory:
       │  ├─ Integrate ODE from its starting IC
       │  └─ Compare to its 150 points
       └─ Sum/average errors across trajectories
           └─ RESULT: Wrong equations fail on at least 1 trajectory
```

---

## Key Data Flow Changes

### Function Signatures That Change

| Function | Before | After |
|----------|--------|-------|
| `discover_derivatives()` | `(t, X, inputs, opts)` | `(experiments, opts)` |
| `refine_with_integration()` | `(candidates, t, X, inputs, opts)` | `(candidates, experiments, opts)` |
| `evaluate_ode_system()` | `(trees, loss_config::IntegrationLoss)` | `(trees, loss_config::IntegrationLoss)` ← same signature but loss_config holds multiple trajs |
| `discover_ode_system()` | Uses `experiments[1]` only | Uses all `experiments` |

### Struct Changes

```julia
# IntegrationLoss - the crucial change
OLD:
    struct IntegrationLoss
        t::Vector{Float64}
        X_observed::Matrix{Float64}
        inputs::Dict
    end

NEW:
    struct IntegrationLoss
        trajectories::Vector{Dict}  # Each: {:t, :X_observed, :inputs}
    end
```

---

## Implementation Steps (Recommended Order)

1. **Add parameter to load_problem()** to enable multiple trajectories
2. **Update data generation** in benchmark modules to support it
3. **Restructure IntegrationLoss** to hold multiple trajectories
4. **Update evaluate_ode_system()** to loop over trajectories
5. **Update refine_with_integration()** to create new-style loss config
6. **Update discover_derivatives()** to combine features from all trajectories
7. **Update discover_ode_system()** to pass experiments vector through
8. **Test and validate** that incorrect equations now get rejected

---

## Why This Works

**Before**: Incorrect equation `dx/dt = x` might fit single trajectory perfectly by coincidence  
**After**: Same wrong equation tested against 3 different trajectories:
- Integrates from IC=1: X=e^t → compares to ground truth → ERROR
- Integrates from IC=2: 2e^t → compares to ground truth → ERROR  
- Integrates from IC=3: 3e^t → compares to ground truth → ERROR
- **Average loss is HIGH** → Equation gets rejected ✅

Meanwhile, the TRUE equation `dx/dt = f(x,t,inputs)`:
- Integrates from IC=1: Matches perfectly → low error
- Integrates from IC=2: Matches perfectly → low error
- Integrates from IC=3: Matches perfectly → low error  
- **Average loss is LOW** → Equation gets selected ✅

---

## Complexity Estimates

| Phase | Effort | Files | Risk |
|-------|--------|-------|------|
| 1. Data generation | Low | 8 benchmark modules | Low |
| 2. Derivative aggregation | Medium | 1 function in SymbolicRegressionODE.jl | Medium |
| 3. Integration evaluation | High | 2-3 functions in SymbolicRegressionODE.jl | High |
| 4. Main function | Low | 1 function in SymbolicRegressionODE.jl | Low |
| Testing & validation | Medium | Example files + new tests | Medium |

**Total effort**: ~2-3 days of implementation + validation

