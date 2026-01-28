# Documentation Index: Multi-Trajectory Evaluation System

This folder now contains comprehensive documentation for implementing multi-trajectory support in the ODE discovery system. This document helps you navigate all the materials.

---

## 📚 Complete Documentation (In Reading Order)

### 1. **START HERE** → [QUICK_REFERENCE.md](QUICK_REFERENCE.md)
**TL;DR version (5 min read)**
- Quick summary of the problem and solution
- The ONE critical function to change
- 5 required changes in priority order
- Pseudo-code showing before/after
- Common questions answered

**Best for**: Getting oriented quickly, understanding the core concept

---

### 2. **Visual Understanding** → [VISUAL_GUIDE.md](VISUAL_GUIDE.md)
**Visual examples and flow diagrams (15 min read)**
- Problem illustration with concrete example
- Before/after system architecture diagrams
- Three critical code change sections
- Execution flow comparisons
- Error metrics visualization
- Summary table of improvements

**Best for**: Visual learners, understanding data flow, seeing the impact

---

### 3. **Implementation Plan** → [IMPLEMENTATION_ROADMAP.md](IMPLEMENTATION_ROADMAP.md)
**Complete roadmap with checklists (30 min read)**
- Executive summary
- 5 changes explained in detail
- File-by-file implementation checklist
- Phase-by-phase breakdown
- Expected improvements and challenges
- Validation approach
- Success criteria

**Best for**: Planning implementation, project management, staying organized

---

### 4. **Detailed Analysis** → [ANALYSIS_MULTIPLE_INITIAL_CONDITIONS.md](ANALYSIS_MULTIPLE_INITIAL_CONDITIONS.md)
**Deep technical analysis (45 min read)**
- Complete problem statement
- Current architecture documentation
- Data generation pipeline
- Evaluation pipeline  
- All key functions & data structures explained
- Required changes for all 5 phases
- Summary of file changes
- Implementation priority
- Potential challenges with solutions

**Best for**: Technical deep-dive, understanding current system, comprehensive reference

---

### 5. **Change Summary** → [CHANGES_NEEDED.md](CHANGES_NEEDED.md)
**Structured summary of all changes (20 min read)**
- The problem illustrated
- 5 specific changes with "before/after" code
- Architecture before vs after
- Key data flow changes
- Function signature changes
- Struct changes
- Implementation steps in order
- Complexity estimates per phase

**Best for**: Quick reference during implementation, seeing specific changes needed

---

### 6. **Concrete Code Examples** → [CODE_EXAMPLES.md](CODE_EXAMPLES.md)
**Ready-to-adapt code snippets (60 min read)**
- Data generation layer changes with full example
- Stage 1 derivative discovery implementation
- Stage 2 integration evaluation implementation
- Main entry point updates
- Usage examples for updated code
- New test file example

**Best for**: Actual implementation, copy-paste starting points, understanding syntax

---

## 📖 How to Use These Documents

### Scenario 1: "I'm completely new to this"
1. Read [QUICK_REFERENCE.md](QUICK_REFERENCE.md) (5 min)
2. Read [VISUAL_GUIDE.md](VISUAL_GUIDE.md) (15 min)
3. Skim [IMPLEMENTATION_ROADMAP.md](IMPLEMENTATION_ROADMAP.md) (10 min)
4. Ready to implement!

**Time**: ~30 minutes

### Scenario 2: "I need to implement this"
1. Read [IMPLEMENTATION_ROADMAP.md](IMPLEMENTATION_ROADMAP.md) - use the checklist
2. Keep [CHANGES_NEEDED.md](CHANGES_NEEDED.md) nearby for reference
3. Use [CODE_EXAMPLES.md](CODE_EXAMPLES.md) while coding
4. Refer to [ANALYSIS_MULTIPLE_INITIAL_CONDITIONS.md](ANALYSIS_MULTIPLE_INITIAL_CONDITIONS.md) for tricky parts

**Time**: Implementation time + reference lookups

### Scenario 3: "I need to understand the current system"
1. Read [ANALYSIS_MULTIPLE_INITIAL_CONDITIONS.md](ANALYSIS_MULTIPLE_INITIAL_CONDITIONS.md) - Current Architecture section
2. It documents every function, struct, and data flow

**Time**: ~45 minutes for complete understanding

### Scenario 4: "I'm stuck on something specific"
- Look for keywords in the index below
- Or use Ctrl+F to search across all documents
- [CODE_EXAMPLES.md](CODE_EXAMPLES.md) has ready-to-use solutions

---

## 🔍 Quick Index: Find What You Need

### By Topic

**Problem & Motivation**
- [QUICK_REFERENCE.md](QUICK_REFERENCE.md) - TL;DR section
- [VISUAL_GUIDE.md](VISUAL_GUIDE.md) - Problem Illustration
- [CHANGES_NEEDED.md](CHANGES_NEEDED.md) - Problem Statement

**Architecture & Current System**
- [ANALYSIS_MULTIPLE_INITIAL_CONDITIONS.md](ANALYSIS_MULTIPLE_INITIAL_CONDITIONS.md) - Current Architecture section
- [VISUAL_GUIDE.md](VISUAL_GUIDE.md) - Execution Flow Before section

**The 5 Required Changes**
- [QUICK_REFERENCE.md](QUICK_REFERENCE.md) - 5 Required Changes table
- [CHANGES_NEEDED.md](CHANGES_NEEDED.md) - All 5 with before/after
- [IMPLEMENTATION_ROADMAP.md](IMPLEMENTATION_ROADMAP.md) - Implementation Checklist

**Data Generation**
- [CODE_EXAMPLES.md](CODE_EXAMPLES.md) - Section 1
- [IMPLEMENTATION_ROADMAP.md](IMPLEMENTATION_ROADMAP.md) - Phase 1

**Stage 1 (Derivatives)**
- [CODE_EXAMPLES.md](CODE_EXAMPLES.md) - Section 2
- [ANALYSIS_MULTIPLE_INITIAL_CONDITIONS.md](ANALYSIS_MULTIPLE_INITIAL_CONDITIONS.md) - Feature Extraction Layer
- [VISUAL_GUIDE.md](VISUAL_GUIDE.md) - Point 3 (Feature Aggregation)

**Stage 2 (Integration Evaluation)** - ⚠️ MOST CRITICAL
- [CODE_EXAMPLES.md](CODE_EXAMPLES.md) - Section 3
- [QUICK_REFERENCE.md](QUICK_REFERENCE.md) - The One Critical Function
- [CHANGES_NEEDED.md](CHANGES_NEEDED.md) - Stage 2 subsection
- [ANALYSIS_MULTIPLE_INITIAL_CONDITIONS.md](ANALYSIS_MULTIPLE_INITIAL_CONDITIONS.md) - Integration Evaluation Layer

**Usage & Examples**
- [CODE_EXAMPLES.md](CODE_EXAMPLES.md) - Section 5
- [IMPLEMENTATION_ROADMAP.md](IMPLEMENTATION_ROADMAP.md) - Expected Changes in Code Behavior

**Testing**
- [CODE_EXAMPLES.md](CODE_EXAMPLES.md) - Section 6 (Testing Changes)
- [IMPLEMENTATION_ROADMAP.md](IMPLEMENTATION_ROADMAP.md) - Validation Approach

**Performance**
- [QUICK_REFERENCE.md](QUICK_REFERENCE.md) - Performance Expectations
- [IMPLEMENTATION_ROADMAP.md](IMPLEMENTATION_ROADMAP.md) - Potential Challenges

---

## 📋 File Modification Summary

**Files to create (new)**:
- `aggregate_features_and_derivatives()` function in SymbolicRegressionODE.jl
- `generate_*_experiments_multi()` variants in benchmark problem files
- Optional: New test file `tests/test_multi_trajectory.jl`

**Files to modify (update signatures & logic)**:
- `SymbolicRegressionODE.jl` (4 functions + 1 struct)
- `BenchmarkSystems.jl` (1 function)
- `benchmarkProblems/ChemicalRateProblems/*.jl` (add variants, keep originals)
- `benchmarkProblems/SSystemProblems/*.jl` (add variants)
- `benchmarkProblems/GMAProblems/*.jl` (add variants)
- `benchmarkProblems/RealBiologicalProblems/*.jl` (add variants)
- `example_ode_discovery.jl` (update examples)
- `benchmark_ode_discovery.jl` (add parameter support)
- `tests/test_benchmark.jl` (minor updates if needed)

**Files to update (documentation)**
- `ODE_DISCOVERY_README.md` (add section on multi-trajectory)

---

## 🎯 Implementation Priority

**CRITICAL (do first)**:
1. Update `IntegrationLoss` struct [QUICK_REFERENCE](QUICK_REFERENCE.md#data-flow-changes)
2. Update `evaluate_ode_system()` function [CODE_EXAMPLES.md - Section 3b](CODE_EXAMPLES.md#example-3b-update-evaluate_ode_system-function)
3. Update `refine_with_integration()` [CODE_EXAMPLES.md - Section 4a](CODE_EXAMPLES.md#example-4a-update-refine_with_integration-signature)

**IMPORTANT (affects correctness)**:
4. Generate multiple trajectories [CODE_EXAMPLES.md - Section 1](CODE_EXAMPLES.md#example-1-modify-benchmark-problem-module)
5. Aggregate derivatives [CODE_EXAMPLES.md - Section 2](CODE_EXAMPLES.md#example-2a-aggregate-features-and-derivatives)

**NICE TO HAVE (completeness)**:
6. Update main entry points [CODE_EXAMPLES.md - Section 4](CODE_EXAMPLES.md#4-main-entry-point-changes)
7. Add tests and examples [CODE_EXAMPLES.md - Section 5-6](CODE_EXAMPLES.md#5-usage-examples)

---

## ✅ Validation Checklist

Use this to verify your implementation:

- [ ] Single trajectory loading still works (backward compat)
- [ ] Multiple trajectory loading works
- [ ] `evaluate_ode_system()` loops over all trajectories
- [ ] Loss is averaged across trajectories
- [ ] Stage 1 uses combined features/derivatives
- [ ] `discover_ode_system()` passes all experiments to both stages
- [ ] Results improve with more trajectories
- [ ] No major performance regression
- [ ] Examples run successfully
- [ ] Tests pass

---

## 🤔 Frequently Asked Questions

**Q: Which file should I modify first?**
A: Start with `SymbolicRegressionODE.jl` - update `IntegrationLoss` and `evaluate_ode_system()` first.

**Q: What's the most critical change?**
A: `evaluate_ode_system()` - this is where wrong equations get filtered. See [QUICK_REFERENCE.md](QUICK_REFERENCE.md).

**Q: Can I do this incrementally?**
A: Yes! Phases 1-3 in [IMPLEMENTATION_ROADMAP.md](IMPLEMENTATION_ROADMAP.md) show good breaking points.

**Q: How do I test as I go?**
A: [IMPLEMENTATION_ROADMAP.md](IMPLEMENTATION_ROADMAP.md) has validation approach per phase.

**Q: What if something breaks?**
A: [ANALYSIS_MULTIPLE_INITIAL_CONDITIONS.md](ANALYSIS_MULTIPLE_INITIAL_CONDITIONS.md) has potential challenges section.

**Q: Where's the actual code I need to write?**
A: [CODE_EXAMPLES.md](CODE_EXAMPLES.md) - ready-to-adapt implementations for all changes.

---

## 📞 Cross-References

These documents frequently reference each other:

```
QUICK_REFERENCE ──→ VISUAL_GUIDE
        ↓                ↓
IMPLEMENTATION ←── CHANGES_NEEDED
   ROADMAP                ↓
        ↓            ANALYSIS
   ROADMAP           (detailed)
        ↓                ↓
   CODE_EXAMPLES ←────────┘
```

**Reading recommendation**: Start at QUICK_REFERENCE, follow arrows based on your needs.

---

## 📊 Document Statistics

| Document | Length | Time to Read | Level |
|----------|--------|-------------|-------|
| QUICK_REFERENCE.md | 6 KB | 5 min | Beginner |
| VISUAL_GUIDE.md | 12 KB | 15 min | Intermediate |
| IMPLEMENTATION_ROADMAP.md | 14 KB | 30 min | Intermediate |
| ANALYSIS_*.md | 18 KB | 45 min | Advanced |
| CHANGES_NEEDED.md | 10 KB | 20 min | Intermediate |
| CODE_EXAMPLES.md | 22 KB | 60 min | Advanced |
| **TOTAL** | **~82 KB** | **~2.5 hours** | - |

---

## 🚀 Getting Started Now

1. **Read QUICK_REFERENCE.md** (5 min)
2. **Read VISUAL_GUIDE.md** (15 min)
3. **Open CODE_EXAMPLES.md** alongside your IDE
4. **Start with Section 1** (data generation - easiest)
5. **Then Section 3** (integration evaluation - most critical)
6. **Test frequently** using examples

**You'll be done in 2-3 hours!**

---

## 📝 Notes for Future Reference

This is your implementation guide for the multi-trajectory evaluation system. Keep all these documents together as reference material during implementation.

**Key insight to remember**: A true differential equation is a **universal law** that applies to ALL initial conditions. By testing against multiple trajectories, you force candidates to satisfy this universality.

---

## Document Metadata

- **Created**: January 28, 2026
- **Purpose**: Guide implementation of multi-trajectory evaluation
- **Total Pages**: ~30 (across all documents)
- **Code Examples**: 25+
- **Diagrams**: 10+
- **Checklists**: 5+

