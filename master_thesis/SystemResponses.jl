using Plots, Random
module SystemResponsesModule
export linear_controlled_system_response, harmonic_oscillator_response, predator_prey_system

function linear_controlled_system_response(t, u; a=1.0, b=1.0, error_std=0.0)
    h = Float64(t.step) # Get the time step. TODO: variable timesteps
    x = zeros(length(t)) # Initialize state array
    x[1] = 0.0           # Initial temperature
    
    for i in 1:length(t)-1
        u_t = u[i]
        dxdt = -a * x[i] + b * u_t
        x[i+1] = x[i] + dxdt * h
    end

    return x + error_std .* randn(length(x))
end

function harmonic_oscillator_response(t, u; omega=1.0, zeta=0.1, k=1.0, error_std=0.0)
    """
    Simulate a damped harmonic oscillator with control input
    dx1/dt = x2
    dx2/dt = -omega^2 * x1 - 2*zeta*omega*x2 + k*u
    
    Parameters:
    - t: time vector
    - u: control input vector
    - omega: natural frequency
    - zeta: damping ratio
    - k: input gain
    - error_std: standard deviation of measurement noise
    """
    h = Float64(t.step) # Get the time step
    n = length(t)
    x1 = zeros(n) # Position
    x2 = zeros(n) # Velocity
    
    # Initial conditions
    x1[1] = 0.0
    x2[1] = 0.0
    
    for i in 1:n-1
        u_t = u[i]
        # State derivatives
        dx1dt = x2[i]
        dx2dt = -omega^2 * x1[i] - 2*zeta*omega*x2[i] + k*u_t
        
        # Euler integration
        x1[i+1] = x1[i] + dx1dt * h
        x2[i+1] = x2[i] + dx2dt * h
    end
    
    # Add noise to position measurements
    return x1 + error_std .* randn(n)
end

function predator_prey_system(t; alpha=1.0, beta=0.1, delta=0.075, gamma=1.5, x1_0=10.0, x2_0=5.0, error_std=0.0)
    """
    Simulate a predator-prey system (Lotka-Volterra model)
    dx1/dt = alpha * x1 - beta * x1 * x2  (prey population)
    dx2/dt = delta * x1 * x2 - gamma * x2  (predator population)
    
    Parameters:
    - t: time vector
    - alpha: prey growth rate (default 1.0)
    - beta: predation rate (default 0.1)
    - delta: predator efficiency (default 0.075)
    - gamma: predator death rate (default 1.5)
    - x1_0: initial prey population (default 10.0)
    - x2_0: initial predator population (default 5.0)
    - error_std: standard deviation of measurement noise
    
    Returns:
    - x1: prey population over time
    - x2: predator population over time
    """
    h = Float64(t.step) # Get the time step
    n = length(t)
    x1 = zeros(n) # Prey population
    x2 = zeros(n) # Predator population
    
    # Initial conditions
    x1[1] = x1_0
    x2[1] = x2_0
    
    for i in 1:n-1
        # State derivatives (Lotka-Volterra equations)
        dx1dt = alpha * x1[i] - beta * x1[i] * x2[i]
        dx2dt = delta * x1[i] * x2[i] - gamma * x2[i]
        
        # Euler integration
        x1[i+1] = x1[i] + dx1dt * h
        x2[i+1] = x2[i] + dx2dt * h
        
        # Ensure populations stay positive
        x1[i+1] = max(x1[i+1], 0.0)
        x2[i+1] = max(x2[i+1], 0.0)
    end
    
    # Add noise to measurements
    x1_noisy = x1 + error_std .* randn(n)
    x2_noisy = x2 + error_std .* randn(n)
    
    return x1_noisy, x2_noisy
end

end