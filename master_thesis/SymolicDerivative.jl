module SymbolicDerivativeModule
using SymbolicRegression, SavitzkyGolay

export symbolic_derivative

function symbolic_derivative(t, x, c)
    """ 
    calculates the symbolic derivative of x with respect to t and c
    using symbolic regression on the derivative estimated via Savitzky-Golay filter
    """
    h = Float64(t.step)
    deriv_estimate_raw = savitzky_golay(x, 11, 2, deriv=1)
    deriv_estimate_scaled = deriv_estimate_raw.y ./ h

    options_deriv = SymbolicRegression.Options(;
        binary_operators=[+, *, /, -], 
        unary_operators=[cos, sin, exp], # Added sin
        seed=42
    )
    
    t_x_c = vcat(t', x', c')

    hall_of_fame_derivatives = equation_search(
        t_x_c, deriv_estimate_scaled; 
        options=options_deriv, 
        niterations=10, # Run for a few iterations
        parallelism=:multithreading
    )
    dominating_derivatives = calculate_pareto_frontier(hall_of_fame_derivatives)
    trees = [member.tree for member in dominating_derivatives]
    return trees
end

end