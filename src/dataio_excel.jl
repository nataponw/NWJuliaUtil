"""
    save_toexcel(filepath::String, data; sheetName::String="Sheet1", startCell::String="B2")

Write data into an excel file.

The function appends the existing file without clearing out previous contents.
"""
function save_toexcel(filepath::String, data::DataFrames.DataFrame; sheetName::String="Sheet1", startCell::String="B2")
    openmode = (isfile(filepath) ? "rw" : "w")
    XLSX.openxlsx(filepath, mode=openmode) do xfile
        # Ensure that the target sheet exists
        if !XLSX.hassheet(xfile, sheetName)
            XLSX.addsheet!(xfile, sheetName)
        end
        # Write the data into the file
        xsheet = xfile[sheetName]
        XLSX.writetable!(xsheet, data, anchor_cell=XLSX.CellRef(startCell))
    end
    return nothing
end

function save_toexcel(filepath::String, data; sheetName::String="Sheet1", startCell::String="B2")
    openmode = (isfile(filepath) ? "rw" : "w")
    XLSX.openxlsx(filepath, mode=openmode) do xfile
        # Ensure that the target sheet exists
        if !XLSX.hassheet(xfile, sheetName)
            XLSX.addsheet!(xfile, sheetName)
        end
        # Write the data into the file
        xsheet = xfile[sheetName]
        xsheet[startCell, dim=1] = data
    end
    return nothing
end
