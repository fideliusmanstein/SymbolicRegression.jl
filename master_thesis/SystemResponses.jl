using Plots, Random
module SystemResponsesModule
export linear_controlled_system_response

function linear_controlled_system_response(t, c; a=1.0, b=1.0, error_std=0.0)
    h = Float64(t.step) # Get the time step. TODO: variable timesteps
    x = zeros(length(t)) # Initialize state array
    x[1] = 0.0           # Initial temperature
    
    for i in 1:length(t)-1
        u_t = c[i]
        dxdt = -a * x[i] + b * u_t
        x[i+1] = x[i] + dxdt * h
    end

    return x + error_std .* randn(length(x))
end

end