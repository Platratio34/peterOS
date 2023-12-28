local expect = require "cc.expect"

local charset = {}
do                     -- [0-9a-zA-Z]
    for c = 48, 57 do table.insert(charset, string.char(c)) end
    for c = 65, 90 do table.insert(charset, string.char(c)) end
    for c = 97, 122 do table.insert(charset, string.char(c)) end
end

---Creates a random string of given length
---@param length number String length
---@param chars string[]|nil Optional. Charset for random characters, if not provided uses default: <code>0-9,a-z,A-Z</code>
---@return string str Random string of length
function string.randomString(length, chars)
    expect(1, length, 'number')
    chars = chars or charset
    if not length or length <= 0 then return '' end
    math.randomseed(os.epoch('utc')/1000)
    local str = ""
    for i = 1, length do
        str = str .. chars[math.random(1, #chars)]
    end
    return str
end

---Checks if <code class=var>_str1</code> contains <code class=var>_str2</code>
---@param _str1 string String to check in
---@param _str2 string String to check for
---@return boolean contains If <code class=var>_str2</code> is in <code class=var>_str1</code>
function string.cont(_str1, _str2)
    expect(1, _str1, 'string')
    expect(2, _str2, 'string')
    return not (_str1:find(_str2) == nil)
end

---Splits <code class=var>_str1</code> on every occurrence of <code class=var>_sep</code>
---@param _str1 string String to split
---@param _sep string String to split on
---@return string[] sections Sections of <code class=var>_str1</code> split around <code class=var>_sep</code>
function string.split(_str1, _sep)
    expect(1, _str1, 'string')
    expect(2, _sep, 'string')
    if not _str1:cont(_sep) then return { _str1 } end
    if not _str1:ends(_sep) then _str1 = _str1 .. _sep end
    local t = {}
    -- for str in _str1:gmatch("([^".._sep.."]+)") do
    for str in string.gmatch(_str1, "(.-)([" .. _sep .. '])') do
        table.insert(t, str)
    end
    return t
end

---Checks if <code class=var>_str1</code> starts with <code class=var>_str2</code>
---@param _str1 string String to check in
---@param _str2 string String to check for
---@return boolean starts If <code class=var>_str1</code> starts with <code class=var>_str2</code>
function string.start(_str1, _str2)
    expect(1, _str1, 'string')
    expect(2, _str2, 'string')
    if _str1:cont(_str2) then
        return _str1:find(_str2) == 1
    else
        return false
    end
end

---Checks if <code class=var>_str1</code> ends with <code class=var>_str2</code>
---@param _str1 string String to check in
---@param _str2 string String to check for
---@return boolean ends If <code class=var>_str1</code> ends with <code class=var>_str2</code>
function string.ends(_str1, _str2)
    expect(1, _str1, 'string')
    expect(2, _str2, 'string')
    if _str1:len() < _str2:len() then
        return false
    end
    if _str1:sub(-_str2:len()) == _str2 then
        return true
    end
    return false
end