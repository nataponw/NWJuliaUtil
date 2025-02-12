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
