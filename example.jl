using SymbolicRegression, SavitzkyGolay

# X = randn(Float32, 5, 100)
# y = 2 * cos.(X[4, :]) + X[1, :] .^ 2 .- 2

t = 0:0.1:10
true_signal = sin.(t)
true_derivative = cos.(t)
noisy_signal = true_signal .+ 0.1 .* randn(length(t))

println("Noisy data generated", noisy_signal)

# 2. Apply the filter to get the derivative
#    window_size=11, polynomial_order=2, derivative_order=1
deriv_estimate = savitzky_golay(noisy_signal, 11, 2, deriv=1)

h = Float64(t.step)
deriv_estimate_scaled = deriv_estimate.y ./ h

# show types and shapes of X, y_test
# println("Type of X: ", typeof(X), ", size: ", size(X))
# println("Type of y: ", typeof(y), ", size: ", size(y))

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

for member in dominating
    complexity = compute_complexity(member, options)
    loss = member.loss
    string = string_tree(member.tree, options)

    println("$(complexity)\t$(loss)\t$(string)")
end

println("\nBest equation found:")
println(string_tree(tree, options))
println("Did evaluation succeed? ", did_succeed)
