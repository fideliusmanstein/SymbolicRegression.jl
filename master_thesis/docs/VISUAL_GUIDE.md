# Visual Guide: Multiple Initial Conditions Implementation

## Problem Illustration

### Single Trajectory Problem (Current)
```
Actual ODE System:
  dx/dt = -x  (TRUE equation)

Candidate A (WRONG):
  dx/dt = -2x  (different decay rate)

Candidate B (WRONG):
  dx/dt = x    (growth instead of decay)

Testing with 1 trajectory (IC: x₀=1.0, t=[0..3]):
  True equation:  x(t) = e^(-t)      → Loss: ~0.001 ✓ Selected (correct)
  Candidate A:    x(t) = e^(-2t)     → Loss: ~0.01 
  Candidate B:    x(t) = e^(t)       → Loss: ~1000
  
  Result: TRUE equation wins ✓

BUT - if by chance Candidate A and Candidate B fit the 
noise/derivative estimate well...

Testing with 1 trajectory (IC: x₀=2.0 with noise, derived incorrectly):
  True equation:  x(t) = 2e^(-t)     → Loss: ~0.05
  Candidate A:    x(t) = 2e^(-2t)    → Loss: ~0.02 ✗ WINS (WRONG!)
  Candidate B:    x(t) = 2e^(t)      → Loss: ~2000
  
  Result: WRONG equation wins ✗ (Problem: overfitting to noise/derivative error)
```

### Multi-Trajectory Solution (After Changes)
```
Testing with 3 trajectories:

Trajectory 1 (IC: x₀=1.0):
  True:       x(t) = e^(-t)         → Loss: 0.001
  Candidate A: x(t) = e^(-2t)       → Loss: 0.05   [Different curve shape]
  Candidate B: x(t) = e^(t)         → Loss: 1000   [Exponential growth]

Trajectory 2 (IC: x₀=2.0):  
  True:       x(t) = 2e^(-t)        → Loss: 0.001
  Candidate A: x(t) = 2e^(-2t)      → Loss: 0.05   [Wrong rate]
  Candidate B: x(t) = 2e^(t)        → Loss: 1000

Trajectory 3 (IC: x₀=3.0):
  True:       x(t) = 3e^(-t)        → Loss: 0.001
  Candidate A: x(t) = 3e^(-2t)      → Loss: 0.05   [Wrong rate - EXPOSED!]
  Candidate B: x(t) = 3e^(t)        → Loss: 1000

Average Loss:
  True equation: (0.001 + 0.001 + 0.001) / 3 = 0.001   ✓ Selected (correct!)
  Candidate A:   (0.05 + 0.05 + 0.05) / 3 = 0.05      
  Candidate B:   (1000 + 1000 + 1000) / 3 = 1000

Result: TRUE equation wins regardless of noise ✓
```

---

## Code Changes: Three Critical Points

### Point 1: Data Structure Change
```julia
# ========== Current ==========
experiments::Vector{Dict} = [
    Dict(
        :t => [0.0, 0.1, 0.2, ..., 3.0],
        :X => [1.0  0.9  0.81  ..., 0.049],  # Single IC
        :inputs => {...}
    )
]

# ========== After Change ==========
experiments::Vector{Dict} = [
    Dict(
        :t => [0.0, 0.1, 0.2, ..., 3.0],
        :X => [1.0  0.9  0.81  ..., 0.049],  # IC = 1.0
        :inputs => {...}
    ),
    Dict(
        :t => [0.0, 0.1, 0.2, ..., 3.0],
        :X => [2.0  1.8  1.62 ..., 0.098],   # IC = 2.0
        :inputs => {...}
    ),
    Dict(
        :t => [0.0, 0.1, 0.2, ..., 3.0],
        :X => [3.0  2.7  2.43 ..., 0.147],   # IC = 3.0
        :inputs => {...}
    )
]
```

### Point 2: Loss Evaluation Change
```julia
# ========== Current ==========
function evaluate_ode_system(trees::Vector, loss_config::IntegrationLoss)
    x0 = loss_config.X_observed[1, :]           # Single IC
    sol = solve(prob, ..., saveat=loss_config.t)
    return mean((sol.u .- loss_config.X_observed).^2)  # Single comparison
end

# ========== After Change ==========
function evaluate_ode_system(trees::Vector, loss_config::IntegrationLoss)
    total_loss = 0.0
    
    # Evaluate on EACH trajectory
    for traj in loss_config.trajectories
        x0 = traj[:X_observed][1, :]    # Different IC each iteration
        sol = solve(prob, ..., saveat=traj[:t])
        loss_i = mean((sol.u .- traj[:X_observed]).^2)
        total_loss += loss_i
    end
    
    # Return averaged loss
    return total_loss / length(loss_config.trajectories)
end
```

### Point 3: Feature Aggregation in Stage 1
```julia
# ========== Current ==========
function discover_derivatives(t, X, inputs, opts)
    dX = compute_numerical_derivatives(t, X)           # 1 trajectory
    features = create_feature_matrix(t, X, inputs)     # N_points × N_features
    
    for state in 1:n_states
        hall_of_fame = equation_search(features, dX[:, state], ...)
        # Learns from ~100-200 data points
    end
end

# ========== After Change ==========
function discover_derivatives(experiments, opts)
    all_features = []
    all_derivatives = []
    
    # Collect from all trajectories
    for exp in experiments
        dX = compute_numerical_derivatives(exp[:t], exp[:X])
        features = create_feature_matrix(exp[:t], exp[:X], exp[:inputs])
        push!(all_features, features)
        push!(all_derivatives, dX)
    end
    
    # Concatenate all data
    combined_features = hcat(all_features...)     # More columns
    combined_derivatives = vcat(all_derivatives...)  # More rows
    
    for state in 1:n_states
        hall_of_fame = equation_search(combined_features, combined_derivatives[:, state], ...)
        # Learns from ~300-600 data points (3× more!)
    end
end
```

---

## Execution Flow: Before vs After

### BEFORE: Current System
```
experiment_vector
    ↓
discover_ode_system()
    ├─ exp = experiments[1]  ← ONLY FIRST
    ├─ Stage 1: discover_derivatives(t, X, inputs)
    │  ├─ dX = numerical_derivatives(t, X)  [150 points]
    │  ├─ features = [t; X; inputs]  [150 × 6 matrix]
    │  └─ Symbolic regression on 150 data points
    │
    ├─ Stage 2: refine_with_integration(candidates, t, X, inputs)
    │  ├─ loss_config = IntegrationLoss(t, X, inputs)
    │  ├─ For each combination:
    │  │  ├─ Integrate ODE from x0=X[1,:]
    │  │  ├─ Compare integrated X to X_observed
    │  │  └─ Return MSE loss
    │  └─ Select best combination
    │
    └─ Output: (best_trees, loss, indices)

ISSUE: Overfits to single trajectory
```

### AFTER: Multi-Trajectory System
```
experiment_vector[1..N]
    ↓
discover_ode_system()
    ├─ Stage 1: discover_derivatives(experiments)  ← ALL
    │  ├─ For each exp in experiments:
    │  │  ├─ dX = numerical_derivatives(t, X)  [150 points each]
    │  │  └─ features = [t; X; inputs]  [150 × 6 each]
    │  ├─ Combine: features [150×3 × 6] = 450 points total
    │  └─ Symbolic regression on 450 data points
    │       (Same derivatives satisfy all initial conditions)
    │
    ├─ Stage 2: refine_with_integration(candidates, experiments)
    │  ├─ loss_config = IntegrationLoss(experiments)  ← ALL
    │  ├─ For each combination:
    │  │  ├─ total_loss = 0
    │  │  ├─ For each experiment:
    │  │  │  ├─ Integrate ODE from x0=exp[:X][1,:]
    │  │  │  ├─ Compare to exp[:X]
    │  │  │  └─ total_loss += MSE
    │  │  └─ Return total_loss / n_experiments
    │  └─ Select best combination
    │
    └─ Output: (best_trees, loss, indices)

BENEFIT: Robust to noise, rejects overfitting
```

---

## State Variables Terminology

For reference, using simpleLin system example:

```
States:        [X3, X4, X5]          (3 state variables)
Inputs:        [X1, X2]              (2 input variables)  
Time points:   150                   (13 discrete times, interpolated)

Feature vector format: [t, X3, X4, X5, X1, X2]  (6 features per time point)
```

When combining 3 trajectories:
- Single trajectory: 150 time points × 6 features = 150 data points for symbolic regression
- Three trajectories: 450 time points × 6 features = 450 data points for symbolic regression
  (Even though it's "only" 13 discrete times, solver provides dense output)

---

## Error Metrics Visualization

### Stage 1: Feature Matching (Derivative Estimation)
```
Before (1 trajectory):
  Target (numerical dX/dt): [noisy derivative estimates from 1 run]
  SR finds: f(t, X) that matches these 150 noisy points
  
After (3 trajectories):
  Target: [noisy derivatives from IC1, IC2, IC3 concatenated]
  SR finds: f(t, X) that MUST match all 450 points
           → Noise cancels out, finds true pattern

Benefit: Derivative estimates are more robust
```

### Stage 2: Integration Matching (ODE Solution)
```
Before (1 trajectory, IC=1.0):
  Integrate ODE from x₀=1.0 → X_pred
  Error = ||X_pred - X_observed||
  
After (3 trajectories):
  For IC=1.0: Error₁ = ||X_pred₁ - X_obs₁||
  For IC=2.0: Error₂ = ||X_pred₂ - X_obs₂||
  For IC=3.0: Error₃ = ||X_pred₃ - X_obs₃||
  Total Error = (Error₁ + Error₂ + Error₃) / 3
  
  Wrong equation dx/dt = -2x:
    - Integrates correctly for IC ratios but with wrong rate
    - Each trajectory will have different magnitude of error
    - Averaging catches the systematic bias

Benefit: Systematically wrong equations can't hide
```

---

## Summary Table

| Aspect | Before | After | Benefit |
|--------|--------|-------|---------|
| **Input Data** | 1 trajectory | N trajectories | More variety |
| **Stage 1 Data** | 150 points | 450 points (3×) | Noise reduction |
| **Stage 1 Robustness** | Low (fits noise) | High (noise cancels) | Better derivatives |
| **Stage 2 Tests** | Integrates from 1 IC | Integrates from N ICs | Systematic errors exposed |
| **Stage 2 Metric** | Loss on 1 curve | Avg loss on N curves | Can't overfit |
| **Computational Cost** | Baseline | ~3× (roughly) | Worth it |
| **Probability of Correct Solution** | Moderate | High | Main goal! |

