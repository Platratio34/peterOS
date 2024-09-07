---@class Vector2
---@field x number
---@field y number
---@operator add(Vector2): Vector2
---@operator sub(Vector2): Vector2
---@operator mul(number): Vector2
---@operator div(number): Vector2
local Vector2 = {}
local Vector2MT = { __index = Vector2, type = 'Vector2' }

---Create a new Vector2
---@param x number|Vector2|?
---@param y number?
---@return Vector2
function Vector2.new(x, y)
    expect(1, x, 'number', 'Vector2', 'nil')
    expect(2, y, 'number', 'nil')
    if x == nil and y == nil then
        x = 0
        y = 0
    elseif Vector2.isValid(x) and y == nil then
        ---@cast x Vector2
        y = x.y
        x = x.x
    elseif type(x) == 'number' and y == nil then
        y = x
    end
    local o = {
        x = x,
        y = y
    }
    setmetatable(o, Vector2MT)
    return o
end

function Vector2MT:__add(other)
    if not (Vector2.isValid(other) and Vector2.isValid(self)) then
        error('Can not add non-Vector2 to Vector2', 2)
    end
    return Vector2.new(self.x + other.x, self.y + other.y)
end

function Vector2MT:__sub(other)
    if not (Vector2.isValid(other) and Vector2.isValid(self)) then
        error('Can not subtract non-Vector2 from Vector2', 2)
    end
    if type(self.x) ~= 'number' then error('thing', 2) end
    return Vector2.new(self.x - other.x, self.y - other.y)
end

function Vector2MT:__eq(other)
    if not (Vector2.isValid(other) and Vector2.isValid(self)) then
        error('Can not compare non-Vector2 with Vector2', 2)
    end
    return self.x == other.x and self.y == other.y
end

function Vector2MT:__mul(val)
    if type(self) == 'number' then
        return val * self
    elseif Vector2.isValid(val) then
        ---@cast val Vector2
        return Vector2.new(self.x * val.x, self.y * val.y)
    elseif type(val) ~= 'number' then
        error('Vector2 can only be multiped by a number or Vector2', 2)
    end
    return Vector2.new(self.x * val, self.y * val)
end

function Vector2MT:__div(val)
    if type(val) ~= 'number' then
        error('Vector2 can only be divided by a number', 2)
    end
    return Vector2.new(self.x / val, self.y / val)
end

function Vector2MT:__tostring()
    return ('(%f,%f)'):format(self.x, self.y)
end

function Vector2MT:__call(x, y)
    return Vector2.new(x,y)
end

function Vector2.isValid(object)
    if type(object) ~= 'table' then
        return false
    end
    if getmetatable(object).type ~= Vector2MT.type then
        return false
    end
    if type(object.x) ~= 'number' then
        error('Vector2 had invalid value for x', 2)
    end
    if type(object.y) ~= 'number' then
        error('Vector2 had invalid value for y', 2)
    end
    return true
end

---Get the vector as 2 values
---@return number x
---@return number y
function Vector2:pos()
    return self.x, self.y
end

---Get the length of the vector
---@return number length
function Vector2:length()
    return math.sqrt(self:squareLength())
end

---Get the square length of the vector
---@return number squareLength
function Vector2:squareLength()
    return (self.x * self.x) + (self.y * self.y)
end

---Normalize this vector (make it length 1)
---@return Vector2 this
function Vector2:normalize()
    local length = self:length()
    self.x = self.x / length
    self.y = self.y / length
    return self
end

---Get a new vector that is the normalized version of this vector2
---@return Vector2 normal
function Vector2:normalized()
    return self.new(self):normalize()
end

---Get the grid length of this vector (sum of absolute value of all components)
---@return number gridLength
function Vector2:gridLength()
    return math.abs(self.x) + math.abs(self.y)
end

---Add to this vector
---@param x number|Vector2
---@param y number?
---@return Vector2 this
function Vector2:add(x, y)
    expect(1, x, 'number', 'Vector2')
    expect(2, y, 'number', 'nil')
    if y == nil then
        y = x.y
        x = x.x
        ---@cast x number
    end
    self.x = self.x + x
    self.y = self.y + y
    return self
end

---Get the distance to another vector
---@param x number|Vector2
---@param y number?
---@return number distance
function Vector2:distance(x, y)
    expect(1, x, 'number', 'Vector2')
    expect(2, y, 'number', 'nil')
    if y ~= nil then
        x = Vector2.new(x, y)
        ---@cast x Vector2
    end
    return (self - x):length()
end

---Get the grid distance to another vector (sum of absolute value of all components of the difference in position)
---@param x number|Vector2
---@param y number?
---@return number gridDistance
function Vector2:gridDistance(x, y)
    expect(1, x, 'number', 'Vector2')
    expect(2, y, 'number', 'nil')
    if y ~= nil then
        x = Vector2.new(x, y)
        ---@cast x Vector2
    end
    return (self - x):gridLength()
end

---Get a clone of this vector
---@return Vector2
function Vector2:clone()
    return Vector2.new(self)
end

---Split a Vector2 into its components
---@param x Vector2|number
---@param y number?
---@return number
---@return number
function Vector2.split(x, y)
    if Vector2.isValid(x) then
        return x.x, x.y
    end
    ---@cast x number
    ---@cast y number
    return x, y
end

---Create a new Vector2 from an array
---@param arr number[] Source array
---@param sI number? Starting index in array
---@return Vector2
function Vector2.fromArray(arr, sI)
    expect(1, arr, 'table')
    expect(2, sI, 'number', 'nil')
    sI = sI or 1
    if #arr - (sI - 1) < 2 then
        error('Array must be have at least 2 elements at and beyond start index', 2)
    end
    return Vector2.new(arr[sI], arr[sI+1])
end

return setmetatable({x=0,y=0}, Vector2MT) ---@type Vector2