# BAB
# Estimate the minimum of the output node

struct BAB
    ϵ::Float64
    optimizer::AbstractMathProgSolver
end

function solve(solver::BAB, problem::Problem)
    global_ub, global_ub_point = compute_UB(problem.network, problem.input)
    global_lb = compute_LB(problem.network, problem.input, solver.optimizer)
    # Assume that the constraint is output <= d
    c, d = tosimplehrep(problem.output)
    doms = Tuple{Float64, Hyperrectangle}[(global_lb, problem.input)]
    while global_ub - global_lb > solver.ϵ
        dom = pick_out(doms) # pick_out implements the search strategy
        subdoms = split_dom(dom[2]) # split implements the branching rule
        for i in 1:length(subdoms)
            dom_ub, dom_ub_point = compute_UB(problem.network, subdoms[i]) # Sample
            dom_lb = compute_LB(problem.network, subdoms[i], solver.optimizer) # bounding - call convDual
            if dom_ub < global_ub
                global_ub = dom_ub
                global_ub_point = dom_ub_point
            end
            if dom_lb < global_ub
                add_domain!(doms, (dom_lb, subdoms[i]))
            end
        end
        global_lb = doms[1][1]
    end
    # The minimum is smaller than global_up
    if global_ub < d[1]
        return CounterExampleResult(:SAT)
    else
        return CounterExampleResult(:UNSAT, global_ub_point)
    end
end

# Always pick the oen with smallest lower bound
function pick_out(doms)
    return doms[1]
end

function add_domain!(doms::Vector{Tuple{Float64, Hyperrectangle}}, new::Tuple{Float64, Hyperrectangle})
    rank = length(doms) + 1
    for i in 1:length(doms)
        if new[1] <= doms[i][1]
            rank = i
            break
        end
    end
    insert!(doms, rank, new)
end

# Always split the longest input dimention
# To do: merge with "split_input" in reluVal
function split_dom(dom::Hyperrectangle)
    max_value, index_to_split = findmax(dom.radius)
    return split_interval(dom, index_to_split)
end

# For simplicity
function compute_UB(nnet::Network, subdom::Hyperrectangle)
    points = [subdom.center, low(subdom), high(subdom)]
    values = Vector{Float64}(undef, 0)
    for p in points
        push!(values, sum(compute_output(nnet, p)))
    end
    value, index = findmin(values)
    return (value, points[index])
end


function compute_LB(nnet::Network, subdom::Hyperrectangle, optimizer::AbstractMathProgSolver)
    bounds = get_bounds(nnet, subdom)
    model = JuMP.Model(solver = optimizer)

    neurons = init_neurons(model, nnet)
    add_input_constraint(model, subdom, first(neurons))
    encode_Δ_lp(model, nnet, bounds, neurons)

    J = sum(last(neurons))
    @objective(model, Min, J)
    status = solve(model)

    if status == :Optimal
        return getvalue(J)
    else
        error("Could not find lower bound for subdom: ", subdom)
    end
end