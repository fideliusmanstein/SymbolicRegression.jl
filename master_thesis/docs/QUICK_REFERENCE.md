# Quick Reference: Multi-Trajectory Changes

## TL;DR

**Problem**: Wrong equations fit single trajectory  
**Solution**: Evaluate against multiple initial conditions  
**Key Change**: Modify integration loss evaluation to test all trajectories

---

## The One Critical Function to Change

### evaluate_ode_system() - Before vs After

**BEFORE** (Current - tests ONE trajectory):
```julia
function evaluate_ode_system(trees, loss_config)
    x0 = loss_config.X_observed[1, :]        # Single IC
    sol = solve(ODE, ...)
    return MSE(integrated, observed)          # Single comparison
end
```

**AFTER** (Proposed - tests ALL trajectories):
```julia
function evaluate_ode_system(trees, loss_config)
    total_loss = 0.0
    for trajectory in loss_config.trajectories   # ← Loop over all
        x0 = trajectory[:X_observed][1, :]      # ← Each IC
        sol = solve(ODE, ...)
        total_loss += MSE(integrated, observed)  # ← Accumulate
    end
    return total_loss / length(trajectories)     # ← Average
end
```

**Why**: If an equation only works for one initial condition, it's wrong. True equations work for all.

---

## 5 Required Changes (Priority Order)

| # | Change | File | Difficulty | Impact |
|---|--------|------|------------|--------|
| 1 | Update `IntegrationLoss` struct | SymbolicRegressionODE.jl | ⭐ Low | ⭐⭐ Medium |
| 2 | Update `evaluate_ode_system()` | SymbolicRegressionODE.jl | ⭐⭐ Medium | ⭐⭐⭐ Critical |
| 3 | Update `refine_with_integration()` | SymbolicRegressionODE.jl | ⭐ Low | ⭐⭐ Medium |
| 4 | Update `discover_derivatives()` | SymbolicRegressionODE.jl | ⭐⭐ Medium | ⭐⭐ Medium |
| 5 | Generate multiple trajectories | benchmarkProblems/*.jl | ⭐ Low | ⭐ Low |

---

## Data Flow Changes

### Current (Single Trajectory)
```
experiments[1] 
    ↓
discover_ode_system()
    ├─ Stage 1: Learn dX/dt from exp[1]
    └─ Stage 2: Evaluate ODE from exp[1]
         └─ Loss = MSE(integrated from IC_1, observed_1)
```

### After (Multiple Trajectories)
```
experiments[1..N]
    ↓
discover_ode_system()
    ├─ Stage 1: Learn dX/dt from ALL exps
    └─ Stage 2: Evaluate ODE from ALL exps
         ├─ Loss₁ = MSE(integrated from IC_1, observed_1)
         ├─ Loss₂ = MSE(integrated from IC_2, observed_2)
         ├─ Loss₃ = MSE(integrated from IC_3, observed_3)
         └─ Loss = (Loss₁ + Loss₂ + Loss₃) / 3
```

---

## Code Changes: The Essentials

### 1. Struct Change
```julia
# OLD:
struct IntegrationLoss
    t::Vector; X_observed::Matrix; inputs::Dict
end

# NEW:
struct IntegrationLoss
    trajectories::Vector{Dict}  # [{:t, :X_observed, :inputs}, ...]
end
```

### 2. Function Signature Changes
```julia
# OLD → NEW

# discover_derivatives(t, X, inputs, opts)
discover_derivatives(experiments, opts)

# refine_with_integration(candidates, t, X, inputs, opts)
refine_with_integration(candidates, experiments, opts)

# load_problem(name)
load_problem(name; num_trajectories=1)
```

### 3. Loss Evaluation Loop
```julia
# In evaluate_ode_system():
total_loss = 0.0
for traj in loss_config.trajectories
    # Integrate from traj's initial condition
    # Compute MSE vs traj's observed data
    total_loss += this_traj_loss
end
return total_loss / length(loss_config.trajectories)
```

---

## What Each Change Achieves

**Change 1 (IntegrationLoss struct)**
- Store multiple trajectories instead of one
- Enable new evaluation pattern

**Change 2 (evaluate_ode_system)**
- ✅ Test each candidate on multiple initial conditions
- ✅ Systematically reject wrong equations
- ✅ **THIS IS THE KEY CHANGE**

**Change 3 (refine_with_integration)**
- Pass all experiments to loss evaluation
- No major internal logic change needed

**Change 4 (discover_derivatives)**
- Aggregate features from all trajectories
- More data = better derivative estimates
- Reduces noise sensitivity

**Change 5 (Generate multiple trajectories)**
- Data generation side (lower priority)
- Just loop over different initial conditions

---

## Pseudo-Code: The Full Picture

```
BEFORE:
────────
function discover_ode_system(experiments)
    exp = experiments[1]              # ← PROBLEM: only uses one
    
    # Stage 1
    candidates = discover_derivatives(exp.t, exp.X, exp.inputs, opts)
    
    # Stage 2
    for combo in candidate_combinations
        loss = evaluate_ode_system(combo, 
                    IntegrationLoss(exp.t, exp.X, exp.inputs))
        # Loss based on single trajectory
        # Can overfit!
    end
end

AFTER:
──────
function discover_ode_system(experiments)
    # Use ALL experiments, not just [1]
    
    # Stage 1
    candidates = discover_derivatives(experiments, opts)  # ← ALL
    
    # Stage 2
    loss_config = IntegrationLoss(experiments)  # ← ALL
    for combo in candidate_combinations
        loss = evaluate_ode_system(combo, loss_config)
        # Loss averages across all trajectories
        # Can't overfit single trajectory
    end
end

# Inside evaluate_ode_system:
function evaluate_ode_system(trees, loss_config)
    total_loss = 0.0
    for traj in loss_config.trajectories      # ← NEW: loop here
        x0 = traj[:X_observed][1, :]          # ← NEW: per-trajectory IC
        sol = integrate_ode(trees, x0, traj[:t])
        total_loss += mean_squared_error(sol, traj[:X_observed])
    end
    return total_loss / length(loss_config.trajectories)
end
```

---

## File Modifications Summary

| File | Function(s) | Lines | Type |
|------|-------------|-------|------|
| SymbolicRegressionODE.jl | IntegrationLoss (struct) | ~10 | MODIFY |
| SymbolicRegressionODE.jl | evaluate_ode_system() | ~70 | MODIFY |
| SymbolicRegressionODE.jl | refine_with_integration() | ~20 | MODIFY |
| SymbolicRegressionODE.jl | discover_derivatives() | ~50 | MODIFY + NEW helper |
| SymbolicRegressionODE.jl | aggregate_features_*() | ~50 | NEW function |
| SymbolicRegressionODE.jl | discover_ode_system() | ~10 | MODIFY |
| BenchmarkSystems.jl | load_problem() | ~5 | MODIFY |
| simpleLin.jl & others | generate_*_experiments() | ~30 | NEW variant |
| examples & tests | Various | ~20 | UPDATE to use new param |

---

## Testing Checklist

- [ ] Load problem with 1 trajectory → works (backward compat)
- [ ] Load problem with 3 trajectories → works
- [ ] Single trajectory evaluation → same as before
- [ ] Multiple trajectory evaluation → loops correctly
- [ ] Results with 3 trajectories better than 1
- [ ] No timeout or performance issues
- [ ] Backward compatible - old code still runs

---

## Performance Expectations

| Metric | Single Trajectory | 3 Trajectories | 5 Trajectories |
|--------|------------------|----------------|----------------|
| Data points (Stage 1) | 150 | 450 | 750 |
| ODE integrations (Stage 2) | M per combo | 3M per combo | 5M per combo |
| Expected time | 1× | 2-3× | 3-5× |
| Quality improvement | Baseline | Good | Better |

**Recommendation**: Start with 3 trajectories (good balance)

---

## Success Metrics

```
Before:  Loss = 0.05 (fits single trajectory, but wrong equation)
After:   Loss = 0.02 (fits multiple trajectories, true equation)

Before:  False positive rate = 20% (wrong equations pass)
After:   False positive rate = 5% (multi-trajectory rejects them)

Before:  Stage 1 data points = 150
After:   Stage 1 data points = 450+
```

---

## Key Insight

**The core insight**: A differential equation is a **universal law** that applies to all initial conditions. By testing against multiple trajectories, you force candidates to satisfy this universality. Wrong equations fail because they encode initial-condition-specific artifacts.

```
Wrong equation (fitted to IC=1.0):
  dx/dt = 0.9x + 0.1sin(t)  ← happens to fit IC=1 well
  
Test on IC=2.0:
  Integrated from x₀=2.0 → Error!
  It doesn't work here → Rejected ✓

True equation (general law):
  dx/dt = 0.9x + 0.05sin(t)  ← works universally
  
Test on IC=1.0: ✓
Test on IC=2.0: ✓  
Test on IC=3.0: ✓
→ Selected ✓
```

---

## Where to Start

1. **Read**: [IMPLEMENTATION_ROADMAP.md](IMPLEMENTATION_ROADMAP.md)
2. **Understand**: Structure of current code
3. **Implement Phase 1**: Data generation (easiest)
4. **Implement Phase 2**: Integration evaluation (most critical)
5. **Test**: Run examples, compare results
6. **Refine**: Handle edge cases, optimize

---

## Common Questions

**Q: Do all trajectories need same time points?**
A: Same time outputs recommended, but not required. Integrate to same `saveat` points.

**Q: How many trajectories is optimal?**
A: Start with 3. Usually 3-5 is good balance. More is better but slower.

**Q: How to choose initial conditions?**
A: Scale baseline (1.0, 1.5, 2.0) or random variations work well.

**Q: Will this break backward compatibility?**
A: No - defaults to 1 trajectory, existing code unchanged.

**Q: How much slower will it be?**
A: ~2-3× for 3 trajectories (baseline + 2× integration cost in Stage 2).

