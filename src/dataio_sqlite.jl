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
