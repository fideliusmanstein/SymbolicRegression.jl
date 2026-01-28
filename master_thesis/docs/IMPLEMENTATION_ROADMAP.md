# Implementation Roadmap: Multi-Trajectory Evaluation System

## Executive Summary

Your system currently evaluates symbolic regression candidates on **a single trajectory** (one run with one initial condition). This allows incorrect equations to achieve good results by overfitting to that specific trajectory's noise and measurement errors.

**Solution**: Generate and evaluate against **multiple trajectories with different initial conditions**. Wrong equations will fail on at least one trajectory, while the true equation works for all.

---

## Problem & Solution at a Glance

```
PROBLEM (Current):
  Only 1 initial condition → Equation fits that trajectory → May be wrong equation
  
SOLUTION (After Changes):
  3+ initial conditions → Equation must fit ALL trajectories → Only true equation succeeds
```

### Why This Works
- True differential equations are **invariant** to initial conditions (same form applies everywhere)
- Wrong equations often work for one case but fail for others
- Averaging loss across trajectories exposes systematic errors
- More data points in Stage 1 → better derivative estimation

---

## The 5 Changes You Need to Make

### 1️⃣ **Data Generation** (Easy - 10% effort)
- **Where**: Benchmark problem modules in `benchmarkProblems/`
- **What**: Generate multiple trajectories instead of one
- **How**: Loop over different initial conditions, save all to experiments vector

**Example**:
```julia
# Before: 1 trajectory
experiments = [Dict(:t => t, :X => X, :inputs => inputs)]

# After: 3 trajectories
experiments = [
    Dict(:t => t, :X => X1, :inputs => inputs),  # IC = 1.0
    Dict(:t => t, :X => X2, :inputs => inputs),  # IC = 2.0  
    Dict(:t => t, :X => X3, :inputs => inputs),  # IC = 3.0
]
```

### 2️⃣ **Stage 1 Feature Aggregation** (Medium - 30% effort)
- **Where**: `SymbolicRegressionODE.jl` - `discover_derivatives()` function
- **What**: Combine features and derivatives from ALL trajectories before symbolic regression
- **Why**: More data = less noise, better derivative estimates

**Change**:
```julia
# Before: Learn from 1 trajectory (150 points)
discover_derivatives(t, X, inputs, ode_options)

# After: Learn from N trajectories (450+ points)
discover_derivatives(experiments, ode_options)
    → Aggregate all features and derivatives
    → Pass combined data to symbolic regression
```

**Concrete step**: 
- Create new function `aggregate_features_and_derivatives(experiments)`
- Concatenate features and derivatives from all experiments
- Pass combined data to `equation_search()`

### 3️⃣ **Stage 2 Integration Loss** (Hard - 60% effort) ⚠️ **MOST CRITICAL**
- **Where**: `SymbolicRegressionODE.jl` - `evaluate_ode_system()` and `IntegrationLoss`
- **What**: Evaluate each candidate by integrating ODE from EACH trajectory's initial condition
- **Why**: This is where wrong equations get filtered - they fail on at least one trajectory

**Change**:
```julia
# Before: Test against 1 trajectory
IntegrationLoss(t, X_observed, inputs)
evaluate_ode_system(trees, loss_config)
    → Integrates once from x0 = X_observed[1, :]
    → Returns MSE for that one trajectory

# After: Test against N trajectories
IntegrationLoss([trajectory1, trajectory2, trajectory3])
evaluate_ode_system(trees, loss_config)
    → For each trajectory:
    │   ├─ Integrate from its x0
    │   ├─ Compare to its X_observed
    │   └─ Compute MSE
    → Return AVERAGE MSE across all trajectories
```

**Concrete steps**:
- Update `IntegrationLoss` struct to hold multiple trajectories
- Update `evaluate_ode_system()` to loop over each trajectory
- Integrate ODE separately for each initial condition
- Average the resulting errors

### 4️⃣ **Integrate Stage Functions** (Easy - 5% effort)
- **Where**: `SymbolicRegressionODE.jl` - `discover_ode_system()` and `refine_with_integration()`
- **What**: Pass ALL experiments through both stages instead of just first one
- **How**: Update function signatures and calls

**Changes**:
```julia
# Before:
discover_ode_system(experiments)
    exp = experiments[1]  # ← ONLY FIRST
    discover_derivatives(exp[:t], exp[:X], exp[:inputs], ...)
    refine_with_integration(candidates, exp[:t], exp[:X], exp[:inputs], ...)

# After:
discover_ode_system(experiments)
    discover_derivatives(experiments, ...)  # ← ALL
    refine_with_integration(candidates, experiments, ...)  # ← ALL
```

### 5️⃣ **Update Examples & Tests** (Medium - 10% effort)
- **Where**: Example files and test files
- **What**: Use new `num_trajectories` parameter
- **How**: Pass parameter when loading problems

**Usage**:
```julia
# Load problem with 3 trajectories
experiments = BenchmarkSystems.load_problem("simpleLin1", num_trajectories=3)

# Or backward compatible - defaults to 1
experiments = BenchmarkSystems.load_problem("simpleLin1")
```

---

## File-by-File Implementation Checklist

### Phase 1: Infrastructure (Low Risk)
- [ ] **benchmarkProblems/BenchmarkSystems.jl**
  - [ ] Add `num_trajectories` parameter to `load_problem()`
  - [ ] Pass through to individual problem loaders

- [ ] **benchmarkProblems/ChemicalRateProblems/simpleLin.jl** (and similar)
  - [ ] Create `generate_simplelin_experiments_multi(; num_trajectories=3)`
  - [ ] Vary initial conditions across trajectories
  - [ ] Keep original function for backward compatibility

- [ ] **benchmarkProblems/SSystemProblems/\*.jl**
  - [ ] Same as above for each S-system

- [ ] **benchmarkProblems/GMAProblems/\*.jl**
  - [ ] Same for GMA problems

- [ ] **benchmarkProblems/RealBiologicalProblems/\*.jl**
  - [ ] Same for biological problems

### Phase 2: Core Evaluation Logic (High Priority)
- [ ] **SymbolicRegressionODE.jl - IntegrationLoss struct**
  - [ ] Change field from `(t, X_observed, inputs)` to `trajectories::Vector`
  - [ ] Add backward-compatible constructor for single trajectory

- [ ] **SymbolicRegressionODE.jl - evaluate_ode_system()**
  - [ ] Loop over `loss_config.trajectories`
  - [ ] For each trajectory:
    - [ ] Extract `:t`, `:X_observed`, `:inputs`
    - [ ] Integrate ODE from trajectory's IC
    - [ ] Compute MSE for that trajectory
  - [ ] Average MSE across all trajectories

- [ ] **SymbolicRegressionODE.jl - refine_with_integration()**
  - [ ] Change signature to accept `experiments` not `(t, X, inputs)`
  - [ ] Create loss config: `IntegrationLoss(experiments)`
  - [ ] Rest of logic stays mostly same (evaluate_ode_system handles multiple)

### Phase 3: Derivative Enhancement (Medium Priority)
- [ ] **SymbolicRegressionODE.jl - aggregate_features_and_derivatives() [NEW]**
  - [ ] Loop over all experiments
  - [ ] Compute derivatives for each
  - [ ] Create feature matrix for each
  - [ ] Concatenate all features horizontally
  - [ ] Concatenate all derivatives vertically
  - [ ] Return combined arrays

- [ ] **SymbolicRegressionODE.jl - discover_derivatives()**
  - [ ] Change signature: `(experiments, ode_options)` instead of `(t, X, inputs, ...)`
  - [ ] Call new `aggregate_features_and_derivatives(experiments, ode_options)`
  - [ ] Pass combined features/derivatives to `equation_search()`

### Phase 4: Main Functions (Easy)
- [ ] **SymbolicRegressionODE.jl - discover_ode_system()**
  - [ ] Remove: `exp = experiments[1]`
  - [ ] Update: Pass entire `experiments` to both stages
  - [ ] Add validation: All experiments same # of states

- [ ] **SymbolicRegressionODE.jl - module exports**
  - [ ] May need to export new `aggregate_features_and_derivatives` (optional)

### Phase 5: Testing & Validation (Important)
- [ ] **tests/test_multi_trajectory.jl** [NEW]
  - [ ] Test loading with multiple trajectories
  - [ ] Test structure of returned experiments
  - [ ] Test that loss evaluation works with multiple trajectories
  - [ ] Test comparison: single vs multiple

- [ ] **example_ode_discovery.jl**
  - [ ] Add example with `num_trajectories=3`
  - [ ] Show comparison: single vs multiple
  - [ ] Demonstrate improvement in results

- [ ] **benchmark_ode_discovery.jl**
  - [ ] Add `num_trajectories` parameter to benchmark functions
  - [ ] Allow comparing performance with different # trajectories

- [ ] **tests/test_benchmark.jl**
  - [ ] Update if needed for new function signatures

---

## Expected Changes in Code Behavior

### Before Implementation
```julia
julia> experiments = load_problem("simpleLin1")
julia> length(experiments)
1  # ← Only 1 experiment

julia> discover_ode_system(experiments)
# Uses only experiments[1]
```

### After Implementation
```julia
julia> experiments = load_problem("simpleLin1")
julia> length(experiments)
1  # Still backward compatible!

julia> experiments = load_problem("simpleLin1", num_trajectories=3)
julia> length(experiments)
3  # New capability!

julia> discover_ode_system(experiments)
# Uses ALL 3 experiments in both stages
# Better results expected
```

---

## Expected Improvements

After implementing these changes:

✅ **Stage 1 Benefits**:
- Derivative discovery uses 3× more data (450 points vs 150)
- Noise is averaged out
- Better equation candidates
- Less overfitting to measurement error

✅ **Stage 2 Benefits**:
- Each candidate tested on 3 different initial conditions
- Wrong equations fail on at least one trajectory
- True equation works for all
- Lower integration loss = more robust equations
- Better ODE solver performance (tests from different x0)

✅ **Overall Benefits**:
- Discovered equations more likely to be correct
- Less overfitting to single trajectory's quirks
- Better generalization to new initial conditions
- More robust symbolic regression results

---

## Potential Challenges & Solutions

| Challenge | Mitigation |
|-----------|-----------|
| **Stage 2 gets slow** (3× more integrations) | Parallel evaluation; only test promising candidates early |
| **Trajectories have different time spans** | Use same time points; interpolate if needed |
| **Initial conditions must be carefully chosen** | Start with scaled versions (1.0, 1.5, 2.0) |
| **Some problems may timeout** | Increase timeout; run with fewer trajectories |
| **Backward compatibility** | Make `num_trajectories=1` default; new function variants |

---

## Implementation Tips

1. **Start with Phase 1**: Get data generation working first - lowest risk
2. **Test frequently**: After each phase, verify with simple examples
3. **Keep backward compatibility**: Original single-trajectory code should still work
4. **Start with 3 trajectories**: Balance between improvement and computation
5. **Use `verbose=true`** during development to see what's happening
6. **Compare results**: Show improvement with metrics

---

## Validation Approach

After each phase, verify:

```julia
# Phase 1: Can we load multiple trajectories?
experiments = load_problem("simpleLin1", num_trajectories=3)
@assert length(experiments) == 3

# Phase 2: Can we evaluate integration loss on multiple?
# (Manually test evaluate_ode_system with multi-trajectory loss config)

# Phase 3: Do derivatives improve with more data?
# (Compare candidate quality with 1 vs 3 trajectories)

# Phase 4: Does full system work end-to-end?
result = discover_ode_system(experiments)
@assert !isnothing(result.best_trees)

# Phase 5: Do results improve?
# (Compare integration_loss: single vs triple)
```

---

## Next Steps

1. **Read the detailed documents**:
   - [ANALYSIS_MULTIPLE_INITIAL_CONDITIONS.md](ANALYSIS_MULTIPLE_INITIAL_CONDITIONS.md) - Complete analysis
   - [CHANGES_NEEDED.md](CHANGES_NEEDED.md) - Summary of changes
   - [VISUAL_GUIDE.md](VISUAL_GUIDE.md) - Visual examples
   - [CODE_EXAMPLES.md](CODE_EXAMPLES.md) - Concrete code

2. **Implement Phase 1** (data generation)
   - Start with just `simpleLin.jl`
   - Test that multiple trajectories load correctly

3. **Implement Phase 2** (integration evaluation)
   - This is where the magic happens
   - Pay careful attention to error handling

4. **Test incrementally**
   - Use `example_ode_discovery.jl` for quick testing
   - Compare results before and after

5. **Document changes**
   - Update [ODE_DISCOVERY_README.md](ODE_DISCOVERY_README.md)
   - Add multi-trajectory examples

---

## Questions to Consider

- How should initial conditions vary? Scaling? Random? Grid?
- Should all trajectories use same time points?
- How many trajectories is optimal? (3? 5? 10?)
- Should different trajectories have different weights?
- How to handle problems with constraints on initial conditions?

---

## Success Criteria

✅ System completes without errors  
✅ Multiple trajectories load correctly  
✅ Integration evaluation runs on all trajectories  
✅ Results improve compared to single trajectory  
✅ Backward compatible with existing code  
✅ Incorrect equations are rejected more reliably  
✅ Execution time remains reasonable (<2× overhead)  

