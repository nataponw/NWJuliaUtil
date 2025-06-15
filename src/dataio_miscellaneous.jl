"""
    clippy(obj)

Copy an object `obj` into system's clipboard
"""
clippy(obj) = Main.clipboard(sprint(show, "text/tab-separated-values", obj))

"""
    appendtxt(filepath::String, text::String)

Append `text` a text file
"""
function appendtxt(filepath::String, text::String)
    io = open(filepath, "a")
    if length(text) == 0
        write(io, "")
    else
        write(io, text * '\n')
    end
    close(io)
end
