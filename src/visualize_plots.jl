"""
    plotcluster(data::Matrix, label::Vector)

Plot 2D or 3D projected `data` with respective `label`
"""
function plotcluster(data::Matrix, label::Vector)
    p = Plots.plot()
    is3D = size(data)[1] == 3
    if is3D
        for l ∈ sort(unique(label))
            idx = findall(==(l), label)
            Plots.plot!(p, data[1, idx], data[2, idx], data[3, idx], seriestype=:scatter3d, label=string(l), opacity=0.75)
        end
    else
        for l ∈ sort(unique(label))
            idx = findall(==(l), label)
            Plots.plot!(p, data[1, idx], data[2, idx], seriestype=:scatter, label=string(l), opacity=0.75)
        end
    end
    return p
end

"""
    plotseries_percentile(mtx::Matrix; xlab, ylab::String, title, bsort::Bool=false, linealpha=0.10, ylims)

Plot multiple timeseries with the same length from `mtx`, a matrix of (time x observation)

# Keyword Arguments
- `bsort` : sort the series
- `linealpha` : transparency of the original series
"""
function plotseries_percentile(mtx::Matrix; xlab::String="Time", ylab::String="Power(MW)", title::String="", bsort::Bool=false, linealpha=0.10, ylims=:auto)
    pf_pct50 = Statistics.mean(mtx, dims=2)[:]
    pf_pct25 = zero(pf_pct50)
    pf_pct75 = zero(pf_pct50)
    for idx ∈ 1:length(pf_pct50)
        pf_pct25[idx] = StatsBase.quantile(mtx[idx, :], 0.25)
        pf_pct75[idx] = StatsBase.quantile(mtx[idx, :], 0.75)
    end
    if bsort
        sort!(pf_pct50); sort!(pf_pct25); sort!(pf_pct75)
        mtx = sort(mtx, dims=1)
    end
    p = Plots.plot(title=title, xlabel=xlab, ylabel=ylab, ylims=ylims)
    [Plots.plot!(p, mtx[:, iobj], label=nothing, linecolor=:black, linealpha=linealpha) for iobj ∈ 1:(size(mtx)[2])]
    Plots.plot!(p, pf_pct50, label="pct50", linecolor=Plots.palette(:default)[1])
    Plots.plot!(p, pf_pct75, label="pct75", linecolor=Plots.palette(:default)[2])
    Plots.plot!(p, pf_pct25, label="pct25", linecolor=Plots.palette(:default)[3])
    return p
end
