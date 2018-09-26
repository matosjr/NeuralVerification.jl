struct FastLip
    maxIter::Int64
    ϵ0::Float64
    accuracy::Float64
end

function solve(solver::FastLip, problem::Problem)
	# Call FastLin or Call get_bounds in convDual
	# Need bounds and activation patterns for all layers
	bounds, act_pattern = get_bounds()
	result = solve(FastLin(), problem)
	ϵ_fastLin = result.max_disturbance

	C = problem.network.layers[1].weights
	L = zeros(size(C))
	U = zeros(size(C))

	for l in 2:length(problem.network.layers)
		C, L, U = bound_layer_grad(C, L, U, problem.network.layers[l].weights, act_pattern[l])
	end

	v = max.(abs.(C+L), abs.(C+U))
	# To do: find out how to compute g
	ϵ = min(g(problem.input.center)/maximum(abs.(v)), ϵ_fastLin)

	return ifelse(ϵ > minimum(problem.input.radius), Result(:True, ϵ), Result(:False, ϵ))
end

function bound_layer_grad(C::Matrix, L::Matrix, U::Matrix, W::Matrix, D::Vector{Float64})
	n_input = size(C)
	rows, cols = size(W)
	new_C = zeros(rows, n_input)
	new_L = zeros(rows, n_input)
	new_U = zeros(rows, n_input)
	for k in 1:n_input
		for j in 1:rows, i in 1:cols

            u = U[i, k]
            l = L[i, k]
            c = C[i, k]
            w = W[j, i]

            if D[i] == 1
                new_C[j,k] += w*c
                new_U[j,k] += (w > 0) ? u : l
                new_L[j,k] += (w > 0) ? l : u
            elseif D[i] == 0 && w*(c+u)>0

                new_U[j,k] += w*(c+u)
                new_L[j,k] += w*(c+l)
            end
		end
	end
	return (new_C, new_L, new_U)
end