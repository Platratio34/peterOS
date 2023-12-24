local function cont(_str1, _str2)
    return not(string.find(_str1,_str2)==nil)
end

local function start(_str1, _str2)
    if cont(_str1, _str2) then
       return string.find(_str1, _str2) == 1 
    else
        return false
    end 
end

local function split(_str1, _sep)
    if not cont(_str1, _sep) then return {_str1} end
    local t = {}
    for str in string.gmatch(_str1, "([^".._sep.."]+)") do
        table.insert(t, str)
    end
    return t
end

return { cont = cont, start = start, split = split }
