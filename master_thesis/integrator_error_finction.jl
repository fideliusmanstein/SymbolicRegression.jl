using SymbolicRegression, SavitzkyGolay
using DifferentialEquations, Plots, Random, Logging

const RUN_DERIVATIVE_SEARCH = true # Set to 'false' to skip and load from file
const RUN_ODE_SEARCH = true        # Set to 'false' to skip and load from file

const DERIV_RESULTS_DIR = "output/deriv_search" # Changed from FILE to DIR
const ODE_RESULTS_DIR = "output/ode_search"     # Changed from FILE to DIR
const HALL_OF_FAME_FILENAME = "20251110_162032_KChjyC/hall_of_fame.csv" # Default SR output name

Random.seed!(42)

t = 0:0.1:10
h = Float64(t.step) # Get the time step
true_signal = sin.(t)
true_derivative = cos.(t)
noisy_signal = true_signal .+ 0.1 .* randn(length(t))

# Apply the filter and SCALE it
deriv_estimate_raw = savitzky_golay(noisy_signal, 11, 2, deriv=1)
deriv_estimate_scaled = deriv_estimate_raw.y ./ h

# Run SR on the SCALED derivative data
t_matrix = hcat(t')

options_deriv = SymbolicRegression.Options(;
    binary_operators=[+, *, /, -], 
    unary_operators=[cos, sin, exp], # Added sin
    seed=42,
    output_directory=DERIV_RESULTS_DIR # Save results to this file
)

if RUN_DERIVATIVE_SEARCH
    println("--- Starting Initial Search for Derivative Representation ---")
    hall_of_fame_derivatives = equation_search(
        t_matrix, deriv_estimate_scaled; 
        options=options_deriv, 
        niterations=10, # Run for a few iterations
        parallelism=:multithreading
    )
    dominating_derivatives = calculate_pareto_frontier(hall_of_fame_derivatives)
else
    deriv_hof_file = joinpath(DERIV_RESULTS_DIR, HALL_OF_FAME_FILENAME)
    dominating_derivatives = calculate_pareto_frontier(deriv_hof_file)
end


function l2_loss_ode(tree, dataset, options)
    function derivative_ode_func(u, p_tree, t)
        t_matrix = hcat([t])'
        val, success = eval_tree_array(p_tree, t_matrix, options)
        if success && isfinite(val[1])
            return val[1]
        else
            return 0.0
        end
    end

    t = dataset.X[1, :]
    y = dataset.y
    tspan = (t[1], t[end])

    ode_problem = ODEProblem(derivative_ode_func, y[1], tspan, tree)
    solution = solve(
        ode_problem, 
        AutoTsit5(Rosenbrock23()),
        maxiters=5000,
        saveat=t, 
        abstol=1e-3,
        reltol=1e-3,
        verbose=0,
        # warn_dtmin=false,
        # warn_on_unstable=false
    )

    if SciMLBase.successful_retcode(solution) && length(solution.u) == length(y)
        loss = sum((solution.u .- y).^2) / length(y)
    else
        loss = Inf
    end
    
    return loss
end

guess_trees = [entry.tree for entry in dominating_derivatives]
options_ode = SymbolicRegression.Options(;
    binary_operators=[+, *, /, -], 
    unary_operators=[cos, sin, exp], # Add 'sin' so it can find 'cos(t)'
    loss_function = l2_loss_ode,     # <--- YOUR NEW LOSS FUNCTION
    seed = 42,
    output_directory=ODE_RESULTS_DIR, # Save results to this file
)

with_logger(NullLogger()) do
    if RUN_ODE_SEARCH
        println("--- Starting Search Using Integration Loss ---")
        hall_of_fame_ode = equation_search(
            t_matrix, noisy_signal; 
            options=options_ode,
            niterations = 5, # WARNING: This is very slow. 5 is just for a quick test.
                            # A real search might need 50+.
            parallelism = :multithreading,
            guesses = guess_trees
        )
        dominating_ode = calculate_pareto_frontier(hall_of_fame_ode)
    else
        ode_hof_file = joinpath(ODE_RESULTS_DIR, HALL_OF_FAME_FILENAME)
        dominating_ode = calculate_pareto_frontier(ode_hof_file)
    end
end

# --- 6. PLOT THE FINAL RESULTS ---
if !isempty(dominating_ode)
    # Get the best equation from the ODE-based search
    best_tree = dominating_ode[end].tree # Get the most complex/accurate tree
    
    # Define the derivative function for plotting, capturing the *correct* options
    function plot_ode_func(u, p_tree, t)
         t_matrix_local = hcat([t])'
         # Capture 'options_ode' from the script's scope
         val, success = eval_tree_array(p_tree, t_matrix_local, options_ode)
         return success ? val[1] : 0.0
    end
    
    y0_plot = noisy_signal[1] # Use the same initial condition
    tspan_plot = (t[1], t[end])
    plot_prob = ODEProblem(plot_ode_func, y0_plot, tspan_plot, best_tree)
    
    # Solve with high resolution for a smooth plot
    ode_solution_smooth = solve(plot_prob, Tsit5(), saveat=0.01) 

    # Plot everything
    p = plot(t, true_signal, label="True Signal (sin(t))", linewidth=3, linestyle=:dash, legend=:bottomleft)
    scatter!(p, t, noisy_signal, label="Noisy Signal", markersize=2, alpha=0.6)

    equation_string = string_tree(best_tree, options_ode)
    plot_label = "SR-ODE: " * equation_string
    plot!(p, ode_solution_smooth, label=plot_label, linewidth=3, color=:red)
    plot!(p, title="Symbolic Regression on ODE vs. Noisy Data")
    
    display(p) # Show the plot

else
    println("ODE-based search did not find any valid equations.")
end

println("Script finished.")