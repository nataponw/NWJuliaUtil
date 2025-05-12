module NWJuliaUtil

# Import dependencies =========================================================
import  DataFrames,
        Dates,
        DBInterface,
        Distributions,
        HDF5,
        PlotlyJS,
        Plots,
        Statistics,
        StatsBase,
        SQLite

# Dependencies used by depreciated functions
import  CategoricalArrays,
        Random

# Export ======================================================================
# Visualization with PlotlyJS
export  saveplot,
        plottimeseries,
        plotseries_doublestack,
        plotbar,
        plothistogram,
        plotcontour,
        plotsurface,
        plotheatmap,
        plotvolume,
        plotbox,
        plotmap,
        plotscatter
# Visualization with Plots
export  plotcluster,
        plotseries_percentile
# Data interface
export  save_objtoh5,
        load_h5toobj,
        save_dftodb,
        load_dbtodf,
        list_dbtable,
        clippy,
        appendtxt
# Profile modification
export  generate_cyclicalpattern,
        generate_poissonseries
# Miscellaneous functions
export  merge_posneg,
        split_posneg,
        merge_dfs,
        averageprofile,
        filter_collapse_plot,
        getcolor,
        convert_serialdate_datetime
# Depreciated
export  save_dftoh5,
        load_h5todf,
        loadall_h5todf,
        synthesizeprofile,
        createdummydata,
        equipmentloading

# Visualization with PlotlyJS =================================================
include(joinpath(@__DIR__, "visualize_plotlyjs.jl"))

# Visualization with Plots ====================================================
include(joinpath(@__DIR__, "visualize_plots.jl"))

# Data interface ==============================================================
include(joinpath(@__DIR__, "dataio_hdf5.jl"))
include(joinpath(@__DIR__, "dataio_sqlite.jl"))
include(joinpath(@__DIR__, "dataio_miscellaneous.jl"))

# Profile modification ========================================================
include(joinpath(@__DIR__, "profile_modification.jl"))

# Miscellaneous functions =====================================================

"""
    mergeposneg(dfpos, dfneg; col_valu =:value)

Merge two dataframes representing positive values and negative values into a single bidirectional data.
"""
function merge_posneg(dfpos::DataFrames.DataFrame, dfneg::DataFrames.DataFrame; col_value=:value)
    dfpos_fmt = DataFrames.rename(dfpos, col_value => :pos)
    dfneg_fmt = DataFrames.rename(dfneg, col_value => :neg)
    df = DataFrames.outerjoin(dfpos_fmt, dfneg_fmt, on=setdiff(DataFrames.propertynames(dfpos), [col_value]))
    df[ismissing.(df.pos), :pos] .= 0.0
    df[ismissing.(df.neg), :neg] .= 0.0
    DataFrames.transform!(df, [:pos, :neg] => (-) => col_value)
    DataFrames.select!(df, DataFrames.Not([:pos, :neg]))
    return df
end

"""
    split_posneg(vt::Vector; col_value=:value)

Split a vector of real numbers `vt` into two vectors of positive and negative values
"""
function split_posneg(vt::Vector; bkeepsign=false)
    pos = max.(vt, +0.0)
    neg = min.(vt, -0.0)
    if !bkeepsign
        neg = abs.(neg)
    end
    return (; pos, neg)
end

"""
    merge_dfs(keyDFPairs::Vector{Pair{String, DataFrame}}; col_value::String="value")

Merge multiple dataframes with some common columns including a value column. The value column is renamed according to the respective keys
"""
function merge_dfs(keyDFPairs::Vector{Pair{String, DataFrames.DataFrame}}; col_value::String="value")
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
    filter_collapse_plot(df, filter_dc, keep_cols; f_collapse=sum, col_time=:time, col_value=:value, kwargs...)

Basic processing of `df`, then plot either the timeseries or bar plot

Filter `df` using criteria in `filter_dc`, a dictionary mapping a column as a symbol to the corresponding filter function. Collapse the filtered dataframe to only the `keep_cols` and `col_value`, the value column. Finally, the processed `df` is plotted either as a timeseries plot, or a bar plot.

# Keyword Arguments
- `f_collapse` : a function to collapse the value column, default is `sum`
- `col_time` and `col_value` : overwrite the default column names

See also : [`plottimeseries`](@ref), [`plotbar`](@ref)
"""
function filter_collapse_plot(df, filter_dc, keep_cols; f_collapse=sum, col_time=:time, col_value=:value, kwargs...)
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

Convert a serial date (excel's date) into a datetime with a second precision
"""
function convert_serialdate_datetime(serialdate)
    (fracDay, fullDay) = modf(serialdate)
    fullSecond = round(Int, 86400*fracDay)
    return Dates.DateTime("1899-12-30") + Dates.Day(Int(fullDay)) + Dates.Second(fullSecond)
end

# Depreciated =================================================================
include(joinpath(@__DIR__, "depreciated.jl"))

end
