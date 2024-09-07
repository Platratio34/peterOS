---@class Matrix3x3
---@field r1 number[]
---@field r2 number[]
---@field r3 number[]
---@operator add(Matrix3x3): Matrix3x3
---@operator sub(Matrix3x3): Matrix3x3
---@operator mul(number): Matrix3x3
local Matrix3x3 = {}

local Matrix3x3MT = { __index = Matrix3x3, type = 'Matrix3x3' }

function Matrix3x3.new()
    local o = {}
    setmetatable(o, Matrix3x3MT) ---@cast o Matrix3x3
    o:__init__()
    return o
end

function Matrix3x3:__init__()
    self.r1 = {}
    self.r2 = {}
    self.r3 = {}
    for i=1,3 do
        self.r1[i] = 0
        self.r2[i] = 0
        self.r3[i] = 0
    end
end

function Matrix3x3MT:__add(other)
    if not getmetatable(other) or (getmetatable(other).type ~= Matrix3x3MT.type) then
        error('Can not add non-Matrix3x3 to Matrix3x3', 2)
    end
    local out = Matrix3x3.new()
    for i = 1, 3 do
        out.r1[i] = self.r1[i] + other.r1[i]
        out.r2[i] = self.r2[i] + other.r2[i]
        out.r3[i] = self.r3[i] + other.r3[i]
    end
    return out
end

function Matrix3x3MT:__sub(other)
    if not getmetatable(other) or (getmetatable(other).type ~= Matrix3x3MT.type) then
        error('Can not subtract non-Matrix3x3 from Matrix3x3', 2)
    end
    local out = Matrix3x3.new()
    for i = 1, 3 do
        out.r1[i] = self.r1[i] - other.r1[i]
        out.r2[i] = self.r2[i] - other.r2[i]
        out.r3[i] = self.r3[i] - other.r3[i]
    end
    return out
end

function Matrix3x3MT:__mul(other)
    if not type(other) == 'number' then
        error('Can only multiply Matrix3x3 by number',  2)
    end
    local out = Matrix3x3.new()
    for i = 1, 3 do
        out.r1[i] = self.r1[i] * other
        out.r2[i] = self.r2[i] * other
        out.r3[i] = self.r3[i] * other
    end
    return out
end

function Matrix3x3:transpose()
    local out = Matrix3x3.new()
    out.r1[1] = self.r1[1]
    out.r1[2] = self.r2[1]
    out.r1[3] = self.r3[1]
    
    out.r2[1] = self.r1[2]
    out.r2[2] = self.r2[2]
    out.r2[3] = self.r3[2]
    
    out.r3[1] = self.r1[3]
    out.r3[2] = self.r2[3]
    out.r3[3] = self.r3[3]
    
    return out
end

return Matrix3x3.new()