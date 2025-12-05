include("SystemResponses.jl")
include("SymolicDerivative.jl")

using DifferentialEquations, SymbolicRegression, Logging
using .SymbolicDerivativeModule

t = 0:0.1:10
c = sin.(t) # control input
x = SystemResponsesModule.linear_controlled_system_response(t, c; a=2.0, b=0.5, error_std=0.0);
t_x_c = vcat(t', x', c')

dominating_derivatives = SymbolicDerivativeModule.symbolic_derivative(t, x, c);


function derivative_ode_func(u, p_tree, t)
    t_matrix = hcat([t])'
    try
        val, success = eval_tree_array(p_tree, t_matrix, options_deriv)
        if success && isfinite(val[1])
            return val[1]
        else
            return 0.0
        end
    catch e
        if isa(e, DomainError)
            return 0.0
        else
            rethrow(e)
        end
    end
end

function l2_loss_ode(tree, dataset, options)
    t = dataset.X[1, :]
    x = dataset.y
    tspan = (t[1], t[end])

    ode_problem = ODEProblem(derivative_ode_func, x[1], tspan, tree)
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

    if SciMLBase.successful_retcode(solution) && length(solution.u) == length(x)
        loss = sum((solution.u .- x).^2) / length(x)
    else
        loss = Inf
    end
    
    return loss
end

function symolic_integration(t_x_c, x, dominating_derivatives, options)
    guess_trees = [entry.tree for entry in dominating_derivatives]

    with_logger(NullLogger()) do
        println("--- Starting Search Using Integration Loss ---")
        hall_of_fame_ode = equation_search(
            t_x_c, x; 
            options=options,
            niterations = 5, # WARNING: This is very slow. 5 is just for a quick test.
                            # A real search might need 50+.
            parallelism = :multithreading,
            guesses = guess_trees
        )
        dominating_ode = calculate_pareto_frontier(hall_of_fame_ode)
    return dominating_ode
    end
end

options_deriv = SymbolicRegression.Options(;
    binary_operators=[+, *, /, -], 
    unary_operators=[cos, sin, exp], # Added sin
    seed=42,
    output_directory="output/deriv_search" # Save results to this file
)

options_ode = SymbolicRegression.Options(;
    binary_operators=[+, *, /, -], 
    unary_operators=[cos, sin, exp],
    loss_function=l2_loss_ode,
    seed = 42,
    output_directory="output/ode_search", # Save results to this file
)

symolic_integration(t_x_c, x, dominating_derivatives, options_ode)