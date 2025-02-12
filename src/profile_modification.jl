"""
    generate_cyclicalpattern(nCycle, angleoffset, ΔT; bfullwave::Bool)

Synthesize a profile with a cyclical pattern using a minus cosine function
"""
function generate_cyclicalpattern(nCycle, angleoffset, ΔT; bfullwave::Bool=false)
    pattern = -cos.(range(0, nCycle*2*pi, length=Int(24/ΔT)) .+ angleoffset)
    if !bfullwave
        pattern[findall(pattern .< 0)] .= 0
    end
    return pattern
end

"""
    generate_poissonseries(n::Int, λ::Int)

Generate a random Poisson serie with a mean of `λ` whose sum equals to `n`
"""
function generate_poissonseries(n::Int, λ::Int)
    dist = Distributions.Poisson(λ)
    series = rand(dist, n ÷ λ)
    while sum(series) != n
        if sum(series) < n
            push!(series, rand(dist))
        else
            diff = n - sum(series[1:(end-1)])
            if diff > 0
                series[end] = diff
            else
                pop!(series)
            end
        end
    end
    return series
end
