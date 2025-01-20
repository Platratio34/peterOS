---@class Vector3
---@field x number
---@field y number
---@field z number
---@operator add(Vector3): Vector3
---@operator sub(Vector3): Vector3
---@operator mul(number): Vector3
---@operator div(number): Vector3
local Vector3 = {}
local Vector3MT = { __index = Vector3, type = 'Vector3' }

---Create a new Vector3
---@param x number|Vector3|?
---@param y number?
---@param z number?
---@return Vector3
---@overload fun(x: number, y: number, z: number): Vector3
---@overload fun(vec: Vector3): Vector3
---@overload fun(val: number): Vector3
---@overload fun(): Vector3
function Vector3.new(x, y, z)
    expect(1, x, 'number', 'Vector3', 'nil')
    expect(2, y, 'number', 'nil')
    expect(3, z, 'number', 'nil')
    if x == nil and y == nil and z == nil then
        x = 0
        y = 0
        z = 0
    elseif Vector3.isValid(x) and y == nil and z == nil then
        ---@cast x Vector3
        y = x.y
        z = x.z
        x = x.x
    elseif type(x) == 'number' and y == nil and z == nil then
        y = x
        z = x
    end
    ---@cast x number
    ---@cast y number
    ---@cast z number
    local o = {
        x = x,
        y = y,
        z = z,
    }
    setmetatable(o, Vector3MT)
    return o
end

function Vector3MT:__add(other)
    if not (Vector3.isValid(other) and Vector3.isValid(self)) then
        error('Can not add non-Vector3 to Vector3', 2)
    end
    return Vector3.new(self.x + other.x, self.y + other.y, self.z + other.z)
end

function Vector3MT:__sub(other)
    if not (Vector3.isValid(other) and Vector3.isValid(self)) then
        error('Can not subtract non-Vector3 from Vector3', 2)
    end
    if type(self.x) ~= 'number' then error('thing', 2) end
    return Vector3.new(self.x - other.x, self.y - other.y, self.z - other.z)
end

function Vector3MT:__eq(other)
    if not (Vector3.isValid(other) and Vector3.isValid(self)) then
        error('Can not compare non-Vector3 with Vector3', 2)
    end
    return self.x == other.x and self.y == other.y and self.z == other.z
end

function Vector3MT:__mul(val)
    if type(self) == 'number' then
        return val * self
    elseif Vector3.isValid(val) then
        ---@cast val Vector3
        return Vector3.new(self.x * val.x, self.y * val.y, self.z * val.z)
    elseif type(val) ~= 'number' then
        error('Vector3 can only be multiped by a number or Vector3', 2)
    end
    return Vector3.new(self.x * val, self.y * val, self.z * val)
end

function Vector3MT:__div(val)
    if type(val) ~= 'number' then
        error('Vector3 can only be divided by a number', 2)
    end
    return Vector3.new(self.x / val, self.y / val, self.z / val)
end

function Vector3MT:__tostring()
    return ('(%f,%f,%f)'):format(self.x, self.y, self.z)
end

function Vector3MT:__call(x, y, z)
    return Vector3.new(x,y,z)
end

function Vector3.isValid(object)
    if type(object) ~= 'table' then
        return false
    end
    if getmetatable(object).type ~= Vector3MT.type then
        return false
    end
    if type(object.x) ~= 'number' then
        error('Vector3 had invalid value for x', 2)
    end
    if type(object.y) ~= 'number' then
        error('Vector3 had invalid value for y', 2)
    end
    if type(object.z) ~= 'number' then
        error('Vector3 had invalid value for z', 2)
    end
    return true
end

---Get the vector as 3 values
---@return number x
---@return number y
---@return number z
function Vector3:pos()
    return self.x, self.y, self.z
end

---Get the length of the vector
---@return number length
function Vector3:length()
    return math.sqrt(self:squareLength())
end

---Get the square length of the vector
---@return number squareLength
function Vector3:squareLength()
    return (self.x * self.x) + (self.y * self.y) + (self.z * self.z)
end

---Normalize this vector (make it length 1)
---@return Vector3 this
function Vector3:normalize()
    local length = self:length()
    self.x = self.x / length
    self.y = self.y / length
    self.z = self.z / length
    return self
end

---Get a new vector that is the normalized version of this Vector3
---@return Vector3 normal
function Vector3:normalized()
    return self.new(self):normalize()
end

---Get the grid length of this vector (sum of absolute value of all components)
---@return number gridLength
function Vector3:gridLength()
    return math.abs(self.x) + math.abs(self.y) + math.abs(self.z)
end

---Add to this vector
---@param x number|Vector3
---@param y number?
---@param z number?
---@return Vector3 this
---@overload fun(x: number, y: number, z: number): Vector3
---@overload fun(vec: Vector3): Vector3
function Vector3:add(x, y, z)
    expect(1, x, 'number', 'Vector3')
    expect(2, y, 'number', 'nil')
    expect(3, z, 'number', 'nil')
    if y == nil then
        ---@cast x Vector3
        y = x.y
        z = x.z
        x = x.x
    end
    ---@cast x number
    self.x = self.x + x
    self.y = self.y + y
    self.z = self.z + z
    return self
end

---Get the distance to another vector
---@param x number|Vector3
---@param y number?
---@param z number?
---@return number distance
---@overload fun(x: number, y: number, z: number): number
---@overload fun(vec: Vector3): number
function Vector3:distance(x, y, z)
    expect(1, x, 'number', 'Vector3')
    expect(2, y, 'number', 'nil')
    expect(3, z, 'number', 'nil')
    if y ~= nil then
        x = Vector3.new(x, y, z)
        ---@cast x Vector3
    end
    return (self - x):length()
end

---Get the grid distance to another vector (sum of absolute value of all components of the difference in position)
---@param x number|Vector3
---@param y number?
---@param z number?
---@return number gridDistance
---@overload fun(x: number, y: number, z: number): number
---@overload fun(vec: Vector3): number
function Vector3:gridDistance(x, y, z)
    expect(1, x, 'number', 'Vector3')
    expect(2, y, 'number', 'nil')
    if y ~= nil then
        x = Vector3.new(x, y, z)
        ---@cast x Vector3
    end
    return (self - x):gridLength()
end

---Get a clone of this vector
---@return Vector3
function Vector3:clone()
    return Vector3.new(self)
end

---LH cross product
---@param vec Vector3
---@return number crossProduct
function Vector3:cross(vec)
    return ( (self.y * vec.z) - (self.z * self.y) ) + ( (self.z * vec.x) - (self.x * self.z) ) + ( (self.x * vec.y) - (self.y * self.x) )
end

---Dot product
---@param vec Vector3
---@return number dotProduct
function Vector3:dot(vec)
    return (self.x * vec.x) + (self.y * vec.y) + (self.z * vec.z)
end

---Split a Vector3 into its components
---@param x Vector3|number
---@param y number?
---@param z number?
---@return number x
---@return number y
---@return number z
---@overload fun(x: number, y: number, z: number): number
---@overload fun(vec: Vector3): number
function Vector3.split(x, y, z)
    if Vector3.isValid(x) then
        return x.x, x.y, x.z
    end
    ---@cast x number
    ---@cast y number
    ---@cast z number
    return x, y, z
end

---Create a new Vector3 from an array
---@param arr number[] Source array
---@param sI number? Starting index in array
---@return Vector3
function Vector3.fromArray(arr, sI)
    expect(1, arr, 'table')
    expect(2, sI, 'number', 'nil')
    sI = sI or 1
    if #arr - (sI - 1) < 3 then
        error('Array must be have at least 3 elements at and beyond start index', 2)
    end
    return Vector3.new(arr[sI], arr[sI+1], arr[sI+2])
end

return setmetatable({x=0,y=0,z=0}, Vector3MT) ---@type Vector3