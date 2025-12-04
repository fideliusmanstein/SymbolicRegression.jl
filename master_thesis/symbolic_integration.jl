using SymbolicRegression, SavitzkyGolay
using DifferentialEquations, Plots, Random

Random.seed!(42)

t = 0:0.1:10
h = Float64(t.step) # Get the time step
true_signal = sin.(t)
true_derivative = cos.(t)
noisy_signal = true_signal .+ 0.5 .* randn(length(t))

# Apply the filter and SCALE it
deriv_estimate_raw = savitzky_golay(noisy_signal, 11, 2, deriv=1)
h = Float64(t.step) # Get the time step
deriv_estimate_scaled = deriv_estimate_raw.y ./ h

# Run SR on the SCALED derivative data
t_matrix = hcat(t')
options = SymbolicRegression.Options(;
    binary_operators=[+, *, /, -], 
    unary_operators=[cos, exp],
    seed=42
)
hall_of_fame = equation_search(t_matrix, deriv_estimate_scaled; options=options, parallelism=:multithreading)
dominating = calculate_pareto_frontier(hall_of_fame)

# 1. Define an ODE function that accepts the tree as a parameter 'p'
#    'options' will be "captured" from the global scope
function derivative_from_tree_parametric(u, p_tree, t)
    # p_tree is the symbolic regression tree
    t_matrix = hcat([t])'
    val, success = eval_tree_array(p_tree, t_matrix, options)
    return val[1]
end

# 2. Set up initial conditions and storage
y0 = true_signal[1] # Use the true first point as the integration constant
tspan = (t[1], t[end])
results = [] # To store (mse, solution, tree_string)

trees = [member.tree for member in dominating]
println("Integrating $(length(trees)) candidate equations...")

# 3. Loop, Solve, and Calculate Error for each tree
for tree in trees
    # Pass the current 'tree' as the parameter 'p'
    prob = ODEProblem(derivative_from_tree_parametric, y0, tspan, tree)
    
    # Solve, making sure to save points at the *exact* same times as 't'
    sol = solve(prob, saveat=t)
    
    # Check if the solver was successful
    if SciMLBase.successful_retcode(sol) && length(sol.u) == length(noisy_signal)
        # Calculate MSE against the noisy_signal, as requested
        mse = sum((sol.u .- noisy_signal).^2) / length(noisy_signal)
        
        # Store the results
        tree_string = string_tree(tree, options)
        push!(results, (mse, sol, tree_string))
    else
        # println("Solver failed for tree: $(string_tree(tree, options)). Skipping.")
    end
end

println("Integration and error calculation complete.")

# 4. Sort results by MSE (lowest error first)
sort!(results, by = x -> x[1])

# 5. Get the best 5
num_to_plot = min(5, length(results))
best_results = results[1:num_to_plot]
println("Best $(size(best_results)) solutions selected for plotting.")

# 6. Plot the best 5 against the TRUE signal for visualization
final_plot = plot(t, true_signal, 
                  label="True Signal (sin(t))", 
                  ls=:dash, 
                  lw=3, 
                  color=:black,
                  title="Best 5 Integrated SR Solutions")

plot!(final_plot, noisy_signal, 
      label="Noisy Signal", 
      lw=1, 
      ls=:dot, 
      color=:gray)
      
println("\n--- Best 5 Solutions (Error vs. Noisy Signal) ---")
for (i, (mse, sol, tree_string)) in enumerate(best_results)
    println("Rank $(i): MSE = $(round(mse, digits=6))\tEquation: $(tree_string)")
    
    # Add this solution to the plot
    plot!(final_plot, sol, 
          lw=2,
          label="MSE:$(round(mse, digits=6)), Derivative: $(tree_string)")
end


# Display the final plot
final_plot
