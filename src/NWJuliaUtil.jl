module NWJuliaUtil

# Import dependencies =========================================================
import DataFrames, CategoricalArrays
import SQLite, DBInterface, HDF5
import PlotlyJS, Plots
import Random, Distributions, Statistics, StatsBase, Dates

# Declare export ==============================================================
# Interactive visualization functions with PlotlyJS
export saveplot, plottimeseries, plotbar, plothistogram, plotcontour, plotsurface, plotheatmap, plotvolume, plotbox, plotmap, plotscatter
# Visualization functions with Plots
export plotcluster, plotseries_percentile
# Data interface functions
export save_objtoh5, load_h5toobj, save_dftoh5, load_h5todf, loadall_h5todf, save_dftodb, load_dbtodf, list_dbtable, appendtxt
# Profile modification functions
export generatedailypattern, generatepoissonseries, synthesizeprofile
# Miscellaneous functions
export clippy, createdummydata, mergeposneg, merge_dfs, averageprofile, equipmentloading, df_filter_collapse_plot, getcolor, convert_serialdate_datetime
# Pending retirement

# Interactive visualization functions with PlotlyJS ===========================
include(joinpath(@__DIR__, "VisualizationFunctionsPlotlyJS.jl"))

# Visualization functions with Plots ==========================================
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
function plotseries_percentile(mtx::Matrix; xlab::String="Hours in a year", ylab::String="Power(kW)", title::String="", bsort::Bool=false, linealpha=0.10, ylims=:auto)
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

# Data interface functions ====================================================

"""
    save_objtoh5(filename::String, objname::String, obj)

Save `obj` as an object `objname` in a HDF5 `filename`.

# Supported Object
- A dictionary, tuple, or namedtuple object whose elements are also of the supported types and whose keys are of String types
- A dataframe object whose columns are the supported vectors (1-D Array)
- An array object of basis types
- A scalar object of basic types
- Basic types are AbstractString, Real including Bool, and Array.
- Array of DateTime is supported, but not a singular DateTime.
"""
function save_objtoh5(filename::String, objname::String, obj; mode="w")
    (last(filename, 3) != ".h5") && (filename *= ".h5")
    HDF5.h5open(filename, mode) do conn
        _process_objtoh5(conn, objname, obj)
    end
    return nothing
end

function _process_objtoh5(conn::Union{HDF5.File, HDF5.Group}, objname::String, obj)
    function _process_structuredObject(typeAttr, allKeys, extractionFunction; conn=conn, objname=objname, obj=obj)
        objname ∈ HDF5.keys(conn) && HDF5.delete_object(conn, objname)
        connGroup = HDF5.create_group(conn, objname)
        HDF5.write_attribute(connGroup, "type", typeAttr)
        [_process_objtoh5(connGroup, string(key), extractionFunction(obj, key)) for key ∈ allKeys]
    end
    if obj isa Dict
        _process_structuredObject("dictionary", keys(obj), (obj, key) -> obj[key])
    elseif obj isa DataFrames.DataFrame
        _process_structuredObject("dataframe", DataFrames.propertynames(obj), (obj, key) -> obj[!, key])
    elseif obj isa Tuple
        _process_structuredObject("tuple", keys(obj), (obj, key) -> obj[key])
    elseif obj isa NamedTuple
        _process_structuredObject("namedtuple", keys(obj), (obj, key) -> obj[key])
    else
        HDF5.write_dataset(conn, objname, obj)
    end
    return nothing
end

"""
    load_h5toobj(filename::String, objname::String)

Load `objname` from a HDF5 `filename`.

See also : [`save_objtoh5`](@ref)
"""
function load_h5toobj(filename::String, objname::String)
    (last(filename, 3) != ".h5") && (filename *= ".h5")
    conn = HDF5.h5open(filename)
    obj = _process_h5toobj(conn[objname])
    HDF5.close(conn)
    return obj
end

"""
    load_h5toobj(filename::String)

Load all objects from a HDF5 `filename`.
"""
function load_h5toobj(filename::String)
    (last(filename, 3) != ".h5") && (filename *= ".h5")
    conn = HDF5.h5open(filename)
    obj = Dict([key => _process_h5toobj(conn[key]) for key ∈ keys(conn)])
    HDF5.close(conn)
    return obj
end

function _process_h5toobj(conn::Union{HDF5.Group, HDF5.Dataset})
    (conn isa HDF5.Dataset) && (return HDF5.read(conn))
    attr_type = HDF5.read_attribute(conn, "type")
    if attr_type == "dataframe"
        return DataFrames.DataFrame([col => _process_h5toobj(conn[col]) for col ∈ keys(conn)])
    elseif attr_type == "dictionary"
        return Dict([key => _process_h5toobj(conn[key]) for key ∈ keys(conn)])
    elseif attr_type == "tuple"
        return Tuple([_process_h5toobj(conn[key]) for key ∈ keys(conn)])
    elseif attr_type == "namedtuple"
        return NamedTuple([Symbol(key) => _process_h5toobj(conn[key]) for key ∈ keys(conn)])
    else
        @warn "Encounter an unsupported type!"
    end
end

"""
    save_dftoh5(filename::String, objectname::String, df::DataFrame; col_value=:value)

Save `df` as an object (folder) into a HDF5 file

`df` must be in a long format with only one value column. In order to save memory, indexes are treated and stored as CategoricalArrays, i.e., with levels and levelcode.
"""
function save_dftoh5(filename::String, objectname::String, df::DataFrames.DataFrame; col_value=:value)
    # Establish connection and create group
    fid = HDF5.h5open(filename, "cw")
    objectname ∈ HDF5.keys(fid) && HDF5.delete_object(fid, objectname)
    gid = HDF5.create_group(fid, objectname)
    # Save index columns
    indexcols = setdiff(DataFrames.propertynames(df), [col_value])
    for col ∈ indexcols
        tmpCol = CategoricalArrays.categorical(df[!, col], compress=true)
        HDF5.write_dataset(gid, "idset_" * string(col), CategoricalArrays.levels(tmpCol))
        HDF5.write_dataset(gid, "idlvl_" * string(col), CategoricalArrays.levelcode.(tmpCol))
    end
    # Save the value column
    HDF5.write_dataset(gid, "value_" * string(col_value), df[!, col_value])
    # Close connections
    HDF5.close(gid)
    HDF5.close(fid)
    return nothing
end

"""
    load_h5todf(filename::String, objectname::String)

Load a saved `df` (folder) from a HDF5 file

See also : [`save_dftoh5`](@ref)
"""
function load_h5todf(filename::String, objectname::String)
    fid = HDF5.h5open(filename, "r")
    gid = fid[objectname]
    # reconstruct the dataframe
    df = DataFrames.DataFrame()
    for colkey ∈ [x for x ∈ HDF5.keys(gid) if !contains(x, "idlvl")]
        if contains(colkey, "value")
            colsym = Symbol(replace(colkey, "value_" => ""))
            DataFrames.insertcols!(df, colsym => HDF5.read(gid, colkey))
        elseif contains(colkey, "idset")
            idset = HDF5.read(gid, colkey)
            idlvl = HDF5.read(gid, replace(colkey, "idset_" => "idlvl_"))
            colvalue = idset[idlvl]
            colsym = Symbol(replace(colkey, "idset_" => ""))
            DataFrames.insertcols!(df, colsym => colvalue)
        end
    end
    HDF5.close(fid)
    return df
end

"""
    loadall_h5todf(filename::String)

Load all saved `df` (folder) from a HDF5 file

See also : [`load_h5todf`](@ref)
"""
function loadall_h5todf(filename::String)
    fid = HDF5.h5open(filename, "r")
    listallobject = HDF5.keys(fid)
    HDF5.close(fid)
    data = Dict{String, DataFrames.DataFrame}()
    for objname ∈ listallobject
        df = load_h5todf(filename, objname)
        data[objname] = df
    end
    return data
end

"""
    save_dftodb(dbpath::String, tablename::String, df::DataFrame)

Save `df` as a table in a SQLite database
"""
function save_dftodb(dbpath::String, tablename::String, df::DataFrames.DataFrame)
    db = SQLite.DB(dbpath)
    SQLite.drop!(db, tablename)
    SQLite.load!(df, db, tablename)
end

"""
    load_dbtodf(dbpath::String, tablename::String)

Load a table from a SQLite database as DataFrame
"""
function load_dbtodf(dbpath::String, tablename::String)
    db = SQLite.DB(dbpath)
    df = DataFrames.DataFrame(DBInterface.execute(db, "SELECT * FROM ($tablename)"))
    return df
end

"""
    list_dbtable(dbpath)

List tables in a database
"""
list_dbtable(dbpath) = [x.name for x ∈ SQLite.tables(SQLite.DB(dbpath))]

"""
    appendtxt(filename::String, text::String)

Append `text` a text file
"""
function appendtxt(filename::String, text::String)
    io = open(filename, "a")
    if length(text) == 0
        write(io, "")
    else
        write(io, text * '\n')
    end
    close(io)
end

# Profile modification functions ==============================================
"""
    generatecyclicalpattern(nCycle, angleoffset, ΔT; bfullwave::Bool)

Synthesize a profile with a cyclical pattern using a minus cosine function
"""
function generatecyclicalpattern(nCycle, angleoffset, ΔT; bfullwave::Bool=false)
    pattern = -cos.(range(0, nCycle*2*pi, length=Int(24/ΔT)) .+ angleoffset)
    if !bfullwave
        pattern[findall(pattern .< 0)] .= 0
    end
    return pattern
end

"""
    generatepoissonseries(n::Int, λ::Int)

Generate a random Poisson serie with a mean of `λ` whose sum equals to `n`
"""
function generatepoissonseries(n::Int, λ::Int)
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

"""
    synthesizeprofile(avgprofile::Vector{Float64}, λ::Int; base_rel::Float64, base_fix::Float64)

Synthesize a random profile from `avgprofile` by grouping neighboring values

Neighbors are randomly chosen using a poissonseries whose mean is `λ`

# Keyword Arguments
- `base_rel` : base value as share of the `avgprofile`, default 0.1
- `base_fix` : base value as a fixed quantity, default 0.0

See also: [`generatepoissonseries`](@ref)
"""
function synthesizeprofile(avgprofile::Vector{Float64}, λ::Int; base_rel::Float64=0.1, base_fix::Float64=0.0)
    nts = length(avgprofile)
    # Shift avgprofile
    moveindex = rand(1:nts)
    avgprofile = circshift(avgprofile, moveindex)
    # Generate random sequence
    randomseries = generatepoissonseries(nts, λ)
    deleteat!(randomseries, findall(==(0), randomseries))
    # Synthesize a profile
    synprofile = min.(base_rel * avgprofile .+ base_fix, avgprofile)
    comp_rest = avgprofile .- synprofile
    ind_first = 1
    for interval ∈ randomseries
        ind_last = ind_first + interval - 1
        synprofile[ind_first + (interval ÷ 2)] += sum(comp_rest[ind_first:ind_last])
        ind_first += interval
    end
    # Shift back synprofile
    circshift!(synprofile, -moveindex)
    return synprofile
end

# Miscellaneous functions =====================================================

"""
    clippy(obj)

Copy an object `obj` into system's clipboard
"""
clippy(obj) = Main.clipboard(sprint(show, "text/tab-separated-values", obj))

"""
    createdummydata(nYear, nTime, nRegion, nVariable)

Create a dummy DataFrame with index columns `:year`, `:time`, `:region`, and `:variable`, and the value column `:value`
"""
function createdummydata(nYear, nTime, nRegion, nVariable)
    sYear = 2025 .+ collect(1:nYear)
    sTime = collect(1:nTime)
    sRegion = [Random.randstring(8) for _ ∈ 1:nRegion]
    sVariable = [Random.randstring(8) for _ ∈ 1:nVariable]
    df = DataFrames.crossjoin(
        DataFrames.DataFrame(:year => sYear),
        DataFrames.DataFrame(:time => sTime),
        DataFrames.DataFrame(:region => sRegion),
        DataFrames.DataFrame(:variable => sVariable),
    )
    DataFrames.insertcols!(df, :value => round.(1000*rand(DataFrames.nrow(df)), digits=2))
    return df
end

"""
    mergeposneg(dfpos, dfneg; col_value = :value)

Merge two dataframes representing positive values and negative values into a single bidirectional data.
"""
function mergeposneg(dfpos::DataFrames.DataFrame, dfneg::DataFrames.DataFrame; col_value=:value)
    dfpos_fmt = DataFrames.rename(dfpos, col_value => :pos)
    dfneg_fmt = DataFrames.rename(dfneg, col_value => :neg)
    df = DataFrames.outerjoin(dfpos_fmt, dfneg_fmt, on=setdiff(DataFrames.propertynames(dfpos), [col_value]))
    df[ismissing.(df.pos), :pos] .= 0.0
    df[ismissing.(df.neg), :neg] .= 0.0
    DataFrames.transform!(df, [:pos, :neg] => ((x, y) -> x .- y) => col_value)
    DataFrames.select!(df, DataFrames.Not([:pos, :neg]))
    return df
end

"""
    merge_dfs(keyDFPairs::Vector{Pair{String, DataFrame}}; col_value="value")

Merge multiple dataframes with some common columns including a value column. The value column is renamed according to the respective keys
"""
function merge_dfs(keyDFPairs::Vector{Pair{String, DataFrames.DataFrame}}; col_value="value")
    (length(keyDFPairs) < 2) && return DataFrames.DataFrame()
    mergedDF = DataFrames.rename(keyDFPairs[1].second, col_value => keyDFPairs[1].first)
    for (colName, df) ∈ keyDFPairs[2:end]
        df = DataFrames.rename(df, col_value => colName)
        mergedDF = DataFrames.outerjoin(mergedDF, df, on = intersect(names(mergedDF), names(df)))
    end
    return mergedDF
end

"""
    averageprofile(pf::Vector; Δt=1.0, bseason=true, bufferlength=3, idx_winter=missing, idx_summer=missing)

Process average daily profile from an entire year's profile `pf`

# Keyword Arguments
- `Δt` : lenght of a timestep in [hour]
- `bseason` : separate individual profiles for summer, winter, and transition period
- `bufferlength` : empty space between seasonal profiles
- `idx_winter` and `idx_summer` : boolean vectors indicating winter and summer. If missing, the default German winter and summer days are used. The default assumes that one year has 365 days.
"""
function averageprofile(pf::Vector; Δt=1.0, bseason=true, bufferlength=3, idx_winter=missing, idx_summer=missing)
    winterday_in_DE = Bool.(vcat(ones(59), zeros(275), ones(31)))
    summerday_in_DE = Bool.(vcat(zeros(151), ones(92), zeros(122)))
    ts_in_day = Int(24/Δt)
    tod = repeat(1:ts_in_day, outer=length(pf)÷ts_in_day)
    if bseason
        # Process season indexes
        ismissing(idx_winter) && (idx_winter = repeat(winterday_in_DE, inner=ts_in_day))
        ismissing(idx_summer) && (idx_summer = repeat(summerday_in_DE, inner=ts_in_day))
        df = DataFrames.DataFrame(:tod => tod, :value => pf, :season => ".")
        df[idx_winter, :season] .= "winter"
        df[idx_summer, :season] .= "summer"
        df[.!(idx_summer .| idx_winter), :season] .= "transition"
        df = DataFrames.combine(DataFrames.groupby(df, [:tod, :season]), :value => Statistics.mean => :value)
        DataFrames.sort!(df, [:season, :tod])
        pf_avg = vcat(reshape(df.value, :, 3), zeros(bufferlength, 3))[:][1:(end-bufferlength)]
    else
        df = DataFrames.DataFrame(:tod => tod, :value => pf)
        df = DataFrames.combine(DataFrames.groupby(df, :tod), :value => Statistics.mean => :value)
        DataFrames.sort!(df, :tod)
        pf_avg = df.value
    end
    return pf_avg
end

"""
    equipmentloading(df; col_region=:region, col_value=:value)

Calculate loading factors from time-resolved operation profiles

Loading factor is defined as the ratio of average and peak values. `df` contains time, region, and value columns. The calculation uses the absolute values.
"""
function equipmentloading(df; col_region=:region, col_value=:value)
    df = deepcopy(df)
    df[:, col_value] = abs.(df[:, col_value])
    loading = DataFrames.combine(DataFrames.groupby(df, col_region), col_value => maximum => :peak, col_value => Statistics.mean => :avg)
    DataFrames.select!(loading, :region, [:avg, :peak] => ((x,y) -> x ./ y) => :value)
    loading[isnan.(loading.value), :value] .= 0.0
    return loading
end

"""
    df_filter_collapse_plot(df, filter_dc, keep_cols; f_collapse=sum, col_time=:time, col_value=:value, kwargs...)

Basic processing of `df`, then plot either the timeseries or bar plot

Filter `df` using criteria in `filter_dc`, a dictionary mapping a column as a symbol to the corresponding filter function. Collapse the filtered dataframe to only the `keep_cols` and `col_value`, the value column. Finally, the processed `df` is plotted either as a timeseries plot, or a bar plot.

# Keyword Arguments
- `f_collapse` : a function to collapse the value column, default is `sum`
- `col_time` and `col_value` : overwrite the default column names

See also : [`plottimeseries`](@ref), [`plotbar`](@ref)
"""
function df_filter_collapse_plot(df, filter_dc, keep_cols; f_collapse=sum, col_time=:time, col_value=:value, kwargs...)
    df = DataFrames.deepcopy(df)
    [DataFrames.filter!(col => filter_dc[col], df) for col ∈ keys(filter_dc)]
    df = DataFrames.combine(DataFrames.groupby(df, keep_cols), col_value => f_collapse => col_value)
    # Call `plottimeseries` or `plotbar`
    if col_time ∈ keep_cols
        col_variable = setdiff(keep_cols, [col_time])[1]
        p = plottimeseries(df, col_variable=col_variable, col_time=col_time; kwargs...)
    else
        col_axis = keep_cols[1]; col_variable = keep_cols[2]
        p = plotbar(df, col_axis=col_axis, col_variable=col_variable; kwargs...)
    end
    return p
end

"""
    getcolor(key; colorcode=colorcode)

Fetch an RGBA color from `colorcode`, a global dictionary variable

If the key does not exist, then random a color and update the `colorcode`
"""
function getcolor(key; colorcode=colorcode)
    if key ∉ keys(colorcode)
        tmp = lpad.(rand(0:255, 3), 3, "0")
        colorcode[key] = "rgba($(tmp[1]), $(tmp[2]), $(tmp[3]), 0.5)"
    end
    return colorcode[key]
end

"""
    convert_serialdate_datetime(serialdate)

Convert a serial date into a datetime with a second precision
"""
function convert_serialdate_datetime(serialdate)
    (fracDay, fullDay) = modf(serialdate)
    fullSecond = round(Int, 86400*fracDay)
    return Dates.DateTime("1899-12-30") + Dates.Day(Int(fullDay)) + Dates.Second(fullSecond)
end

# Pending retirement ==========================================================

end
