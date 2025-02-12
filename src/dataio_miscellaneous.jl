"""
    clippy(obj)

Copy an object `obj` into system's clipboard
"""
clippy(obj) = Main.clipboard(sprint(show, "text/tab-separated-values", obj))

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
