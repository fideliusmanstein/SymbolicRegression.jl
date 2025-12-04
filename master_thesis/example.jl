using SymbolicRegression, SavitzkyGolay, DifferentialEquations, Plots

t = 0:0.1:10
true_signal = sin.(t)
true_derivative = cos.(t)
noisy_signal = true_signal .+ 0.1 .* randn(length(t))

println("Noisy data generated", noisy_signal)

deriv_estimate = savitzky_golay(noisy_signal, 11, 2, deriv=1)
h = Float64(t.step)
deriv_estimate_scaled = deriv_estimate.y ./ h

options = SymbolicRegression.Options(;
    binary_operators=[+, *, /, -], unary_operators=[cos, exp]
)
t_matrix = hcat(t')
hall_of_fame = equation_search(t_matrix, deriv_estimate_scaled; options=options, parallelism=:multithreading)
dominating = calculate_pareto_frontier(hall_of_fame)

trees = [member.tree for member in dominating]

tree = trees[end]
output, did_succeed = eval_tree_array(tree, t_matrix, options)

println("Complexity\tMSE\tEquation")

function derivative_from_tree(u, p, t)
    # eval_tree_array expects features as a Matrix (features x samples)
    # For a single time 't', this is a 1x1 matrix.
    t_matrix = hcat([t])'

    # We assume the tree was trained on one variable (time)
    # 'tree' and 'options' must be available in this function's scope
    val, success = eval_tree_array(tree, t_matrix, options)
    
    # Return the scalar derivative value
    return val[1]
end

y0 = true_signal[1]
tspan = (t[1], t[end])

prob = ODEProblem(derivative_from_tree, y0, tspan)

# 3. Solve the Problem
sol = solve(prob)

# 4. Plot and Compare
plot(sol, label="Integrated Solution (from SR tree)", lw=2)
plot!(t, true_signal, label="True Signal (sin(t))", ls=:dash, lw=2)

# for member in dominating
#     complexity = compute_complexity(member, options)
#     loss = member.loss
#     string = string_tree(member.tree, options)

#     println("$(complexity)\t$(loss)\t$(string)")
# end

# println("\nBest equation found:")
# println(string_tree(tree, options))
# println("Did evaluation succeed? ", did_succeed)
