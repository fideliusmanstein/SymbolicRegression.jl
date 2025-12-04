module SymbolicDerivativeModule
using SymbolicRegression, SavitzkyGolay

export symbolic_derivative

function symbolic_derivative(t, x, c)
    h = Float64(t.step)
    deriv_estimate_raw = savitzky_golay(x, 11, 2, deriv=1)
    deriv_estimate_scaled = deriv_estimate_raw.y ./ h

    options_deriv = SymbolicRegression.Options(;
        binary_operators=[+, *, /, -], 
        unary_operators=[cos, sin, exp], # Added sin
        seed=42
    )
    
    t_c_matrix = vcat(t', x', c')

    hall_of_fame_derivatives = equation_search(
        t_c_matrix, deriv_estimate_scaled; 
        options=options_deriv, 
        niterations=10, # Run for a few iterations
        parallelism=:multithreading
    )
    dominating_derivatives = calculate_pareto_frontier(hall_of_fame_derivatives)
    trees = [member.tree for member in dominating_derivatives]
    return trees
end

end