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
    synthesizeprofile(avgprofile::Vector{Float64}, λ::Int; base_rel::Float64, base_fix::Float64)

Synthesize a random profile from `avgprofile` by grouping neighboring values

Neighbors are randomly chosen using a poissonseries whose mean is `λ`

# Keyword Arguments
- `base_rel` : base value as share of the `avgprofile`, default 0.1
- `base_fix` : base value as a fixed quantity, default 0.0

See also: [`generate_poissonseries`](@ref)
"""
function synthesizeprofile(avgprofile::Vector{Float64}, λ::Int; base_rel::Float64=0.1, base_fix::Float64=0.0)
    nts = length(avgprofile)
    # Shift avgprofile
    moveindex = rand(1:nts)
    avgprofile = circshift(avgprofile, moveindex)
    # Generate random sequence
    randomseries = generate_poissonseries(nts, λ)
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
