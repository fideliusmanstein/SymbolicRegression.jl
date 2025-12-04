include("SystemResponses.jl")
include("SymolicDerivative.jl")
using .SymbolicDerivativeModule

t = 0:0.1:10
c = sin.(t) # control input
x = SystemResponsesModule.linear_controlled_system_response(t, c; a=2.0, b=0.5, error_std=0.0);

dominating_derivatives = SymbolicDerivativeModule.symbolic_derivative(t, x, c)