local function printTbl(tbl, file)
    file.write("{")
    local c = false
    for k,v in pairs(tbl) do
        if c then file.write(",") end
        c = true
        if type(k) == "string" then
            file.write(k.."=")
        end
        if not type(v) then
            file.write("nil")
        elseif type(v) == "table" then
            printTbl(v, file)
        elseif type(v) == "string" then
            local str = ""
            local lchar = ""
            for i = 1, #v do
                local char = v:sub(i,i)
                if char == "'" and not (lchar == "\\") then
                    str = str.."\\"
                end
                if char == "\\" and lchar =="\\" then
                    lchar = ""
                end
                str = str..char
                lchar = char
            end            
            file.write("'"..str.."'")
        elseif type(v) == "number" then
            file.write(v)
        elseif type(v) == "boolean" then
            file.write(v)
        end
    end
    file.write("}")
end

local function saveTbl(tbl, filename)
    if fs.exists(filename) then
        if fs.isReadOnly(filename) then
            return false
        end
    end
    local f = fs.open(filename, "w")
    if not f then
        return false
    end

    f.write("return ")
    printTbl(tbl, f)

    f.close()
    return true
end

local function saveF(tbl, filename)
    local f = fs.open(filename, "w")
    f.write(textutils.serialise(tbl))
    f.close()
end

local function loadF(filename)
    local f = fs.open(filename, "r")
    local tbl = textutils.unserialise(f.readAll())
    f.close()
    return tbl
end

return { save = saveTbl, saveF = saveF, loadF = loadF }