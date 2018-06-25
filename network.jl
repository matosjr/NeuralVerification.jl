type Layer
    bias::Matrix{Float64}
    weights::Matrix{Float64}
end

type Network
    layers::Vector{Layer} # layers includes input & output layer
end