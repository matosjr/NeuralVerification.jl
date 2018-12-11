# Certify based on semidefinite relaxation
# NN should only have one layer
# This method only works for half space output constraint
# c y <= d
# Input constraint needs to be a hyperrectangle with uniform radius
struct Certify{O<:AbstractMathProgSolver}
    optimizer::O
end

function solve(solver::Certify, problem::Problem)
    @assert length(problem.network.layers) == 2 "Network should only contain one hidden layer!"
    model = JuMP.Model(solver = solver.optimizer)
    c, d = tosimplehrep(problem.output)
    v = c * problem.network.layers[2].weights
    W = problem.network.layers[1].weights
    M = get_M(v[1, :], W)
    n = size(M, 1)

    # Cone type SDP not supported
    @variable(model, P[1:n, 1:n], SDP)

    # Compute cost
    Tr = M * P
    output = c * compute_output(problem.network, problem.input.center) .- d[1]
    epsilon = problem.input.radius[1]
    J = output + epsilon/4 * sum(Tr[i, i] for i in 1:n)

    # Specify problem
    @constraint(model, diag(P) .<= ones(n))
    @objective(model, Max, J[1])
    status = solve(model)
    return interpret_result(solver, status, J[1])
end

# True if J < 0
# Undertermined if otherwise
function interpret_result(solver::Certify, status, J)
    # println("Upper bound: ", getvalue(J[1]))
    if getvalue(J) <= 0
        return BasicResult(:SAT)
    else
        return BasicResult(:Unknown)
    end
end

# M is used in the semidefinite program
function get_M(v::Vector{Float64}, W::Matrix{Float64})
    m = W' * Diagonal(v)
    mxs, mys = size(m)
    o = ones(size(W, 2), 1)
    # TODO Mrow2 and Mrow3 look suspicious (dims don't match in the general case).
    Mrow1 = [zeros(1, 1+mxs)    o'*m]
    Mrow2 = [zeros(mxs, 1+mxs)     m]
    Mrow3 = [m'*o  m' zeros(mys, mys)]

    M = [Mrow1; Mrow2; Mrow3]
    return M
end