module SymbolicDerivativeModule
using SymbolicRegression, SavitzkyGolay

export symbolic_derivative, symbolic_derivative_multi_state

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

function symbolic_derivative_multi_state(t, x_matrix)
    """ 
    Calculates symbolic derivatives for multiple states simultaneously
    
    Parameters:
    - t: time vector (n,)
    - x_matrix: state matrix where each column is a different state (n, n_states)
    
    Returns:
    - results: Vector of results, one per state, each containing dominating trees
    """
    h = Float64(t.step)
    n_states = size(x_matrix, 2)
    
    # Calculate derivatives for all states
    deriv_estimates = zeros(length(t), n_states)
    for i in 1:n_states
        deriv_raw = savitzky_golay(x_matrix[:, i], 11, 2, deriv=1)
        deriv_estimates[:, i] = deriv_raw.y ./ h
    end
    
    options_deriv = SymbolicRegression.Options(;
        binary_operators=[+, *, /, -], 
        unary_operators=[cos, sin, exp],
        maxsize=10,  # Limit complexity
        seed=42
    )
    
    # Prepare input features: [t, x1, x2, ..., xn]
    X_features = hcat(t, x_matrix)'  # Shape: (n_states+1, n_time)
    
    # Search for derivatives of each state independently
    results = []
    for i in 1:n_states
        println("Searching for derivative of state $i...")
        
        # Target is the derivative of state i
        y_target = deriv_estimates[:, i]
        
        hall_of_fame = equation_search(
            X_features, y_target; 
            options=options_deriv, 
            niterations=10,
            parallelism=:multithreading
        )
        
        dominating = calculate_pareto_frontier(hall_of_fame)
        push!(results, dominating)
    end
    
    return results
end

end