local Vector2 = pos.require('math.Vector2') ---@type Vector2

---@class FrameBuffer
---@field text string[][] Text characters for each pixel
---@field textColor string[][] Text color of each pixel
---@field backColor string[][] Background color of each pixel
---@field width integer Width of the frame buffer
---@field height integer Height of the frame buffer
---@field private __rowCache string[][]
local FrameBuffer = {}
local FrameBufferMT = {
    __index = FrameBuffer,
    type = 'FrameBuffer'
}

---Create a new Frame Buffered
---@param width integer Width of buffer
---@param height integer Height of buffer
---@param solid boolean|string|color|nil If the frame buffer should initialize solid or transparent, or the color to fill with
---@param map string[][]? Row/Column color map to initialize from
---@return FrameBuffer frameBuffer
function _G.pos.gui.FrameBuffer(width, height, solid, map)
    expect(1, width, 'number')
    expect(2, height, 'number')
    expect(3, solid, 'boolean', 'string', 'number', 'nil')
    expect(4, map, 'table', 'nil')
    local o = {
        text = {},
        textColor = {},
        backColor = {},
        width = width,
        height = height,
        __rowCache = { {}, {}, {} }
    }
    if solid == true then
        solid = 'f'
    elseif type(solid) == 'number' then
        solid = colors.toBlit(solid)
    end
    for y = 1, height do
        o.text[y] = {}
        o.textColor[y] = {}
        o.backColor[y] = {}
        for x = 1, width do
            if solid then
                o.text[y][x] = ' '
                o.textColor[y][x] = 'f'
                o.backColor[y][x] = solid
            else
                o.text[y][x] = ''
                o.textColor[y][x] = ' '
                o.backColor[y][x] = ' '
            end
            if map then
                local c = map[y][x]
                if c ~= ' ' then
                    o.text[y][x] = ' '
                end
                o.backColor[y][x] = c
            end
        end
    end
    setmetatable(o, FrameBufferMT)
    return o
end

---Clear the frame buffer and reset all color / text
---@param color string|color|nil
function FrameBuffer:clear(color)
    if type(color) == "number" then
        color = colors.toBlit(color) ---@cast color string
    end
    color = color or 'f'
    for y = 1, self.height do
        for x = 1, self.width do
            self.text[y][x] = ' '
            self.textColor[y][x] = 'f'
            self.backColor[y][x] = color
        end
        self.__rowCache[1][y] = nil
        self.__rowCache[2][y] = nil
        self.__rowCache[3][y] = nil
    end
end

---Set a pixel in the buffer
---@param x integer|Vector2 X position
---@param y integer? Y position
---@param text string? Character to draw at pixel
---@param textColor string|color|nil Color of character of pixel
---@param backColor string|color|nil Background color of pixel
---@return boolean changed If the pixel changed
function FrameBuffer:setPixel(x, y, text, textColor, backColor)
    expect(1, x, 'number', 'Vector2')
    expect(3, text, 'nil', 'string')
    expect(4, textColor, 'nil', 'string', 'number')
    if type(textColor) == 'number' then textColor = colors.toBlit(textColor) end
    ---@cast textColor string?
    expect(5, backColor, 'nil', 'string', 'number')
    if type(backColor) == 'number' then backColor = colors.toBlit(backColor) end
    ---@cast backColor string?
    if Vector2.isValid(x) then
        y = x.y
        x = x.x
    end
    expect(2, y, 'number', 'Vector2')
    ---@cast x number
    ---@cast y number
    x = math.floor(x + 0.5)
    y = math.floor(y + 0.5)
    if x < 1 or x > self.width or y < 1 or y > self.height then
        return false
    end
    local changed = false
    if text and text ~= '' then
        if (self.text[y][x] ~= text) then
            changed = true
            self.__rowCache[1][y] = nil
        end
        self.text[y][x] = text
    end
    if textColor and textColor ~= ' ' then
        if (self.textColor[y][x] ~= textColor) then
            changed = true
            self.__rowCache[2][y] = nil
        end
        self.textColor[y][x] = textColor
    end
    if backColor and backColor ~= ' ' then
        if (self.backColor[y][x] ~= backColor) then
            changed = true
            self.__rowCache[3][y] = nil
        end
        self.backColor[y][x] = backColor
    end
    return changed
end

---Write a line of pixels to the buffer
---@param x integer|Vector2 X position
---@param y integer? Y position
---@param text string Text to write
---@param textColor string|color|nil Color of text
---@param backColor string|color|nil Background color
function FrameBuffer:write(x, y, text, textColor, backColor)
    expect(1, x, 'number', 'Vector2')
    if Vector2.isValid(x) then
        y = x.y
        x = x.x
    end
    expect(2, y, 'number')
    expect(3, text, 'nil', 'string')
    expect(4, textColor, 'nil', 'string', 'number')
    if type(textColor) == 'number' then
        textColor = colors.toBlit(textColor):rep(#text)
    end
    expect(5, backColor, 'nil', 'string', 'number')
    if type(backColor) == 'number' then
        backColor = colors.toBlit(backColor):rep(#text)
    end
    for i = 1, #text do
        local t, tC, bC = nil, nil, nil
        if text then t = text:sub(i, i) end
        if textColor then tC = textColor:sub(i, i) end
        if backColor then bC = backColor:sub(i, i) end
        self:setPixel(x + (i - 1), y, t, tC, bC)
    end
end

local function correctCords(x1, y1, x2, y2)
    x1 = math.floor(x1 + 0.5)
    y1 = math.floor(y1 + 0.5)
    x2 = math.floor(x2 + 0.5)
    y2 = math.floor(y2 + 0.5)

    local minX = math.min(x1, x2)
    local minY = math.min(y1, y2)
    local maxX = math.max(x1, x2)
    local maxY = math.max(y1, y2)

    return minX, minY, maxX, maxY
end

---Draw a line
---@param color string|color Line color
---@param x1 number|Vector2
---@param y1 number|Vector2
---@param x2 number
---@param y2 number
---@overload fun(self: FrameBuffer, color: string, x1: number, y1: number, x2: number, y2: number)
---@overload fun(self: FrameBuffer, color: string, p1: Vector2, p2: Vector2)
function FrameBuffer:drawLine(color, x1, y1, x2, y2)
    expect(1, color, 'string', 'number')
    if type(color) == 'number' then
        color = colors.toBlit(color)
    end
    expect(2, x1, 'number', 'Vector2')
    expect(3, y1, 'number', 'Vector2')
    if Vector2.isValid(x1) and Vector2.isValid(y1) then
        ---@cast x1 Vector2
        ---@cast y1 Vector2
        x2 = y1.x
        y2 = y1.y

        y1 = x1.y
        x1 = x1.x
    elseif Vector2.isValid(x1) or Vector2.isValid(y1) then
        error('Arguments 2 and 3 must both be number or Vector2', 2)
    end
    expect(4, x2, 'number')
    expect(5, y2, 'number')
    ---@cast x1 number
    ---@cast y1 number

    x1 = math.floor(x1 + 0.5)
    y1 = math.floor(y1 + 0.5)
    x2 = math.floor(x2 + 0.5)
    y2 = math.floor(y2 + 0.5)

    if x1 == x2 and y1 == y2 then
        self:setPixel(x1, y1, ' ', nil, color)
        return
    end

    local minX = math.min(x1, x2)
    local maxX, minY, maxY
    if minX == x1 then
        minY = y1
        maxX = x2
        maxY = y2
    else
        minY = y2
        maxX = x1
        maxY = y1
    end

    local xDiff = maxX - minX
    local yDiff = maxY - minY

    if math.abs(xDiff) > math.abs(yDiff) then
        local y = minY
        local dy = yDiff / xDiff
        for x = minX, maxX do
            self:setPixel(x, math.floor(y + 0.5), ' ', nil, color)
            y = y + dy
        end
    else
        local x = minX
        local dx = xDiff / yDiff
        if maxY >= minY then
            for y = minY, maxY do
                self:setPixel(math.floor(x + 0.5), y, ' ', nil, color)
                x = x + dx
            end
        else
            for y = minY, maxY, -1 do
                self:setPixel(math.floor(x + 0.5), y, ' ', nil, color)
                x = x - dx
            end
        end
    end
end

---Draw a rectangle
---@param color string|color Color
---@param x1 number|Vector2
---@param y1 number|Vector2
---@param x2 number
---@param y2 number
---@overload fun(self: FrameBuffer, color: string, x1: number, y1: number, x2: number, y2: number)
---@overload fun(self: FrameBuffer, color: string, p1: Vector2, p2: Vector2)
function FrameBuffer:drawRect(color, x1, y1, x2, y2)
    expect(1, color, 'string', 'number')
    if type(color) == 'number' then
        color = colors.toBlit(color)
    end
    expect(2, x1, 'number', 'Vector2')
    expect(3, y1, 'number', 'Vector2')
    if Vector2.isValid(x1) and Vector2.isValid(y1) then
        ---@cast x1 Vector2
        ---@cast y1 Vector2
        x2 = y1.x
        y2 = y1.y

        y1 = x1.y
        x1 = x1.x
    elseif Vector2.isValid(x1) or Vector2.isValid(y1) then
        error('Arguments 2 and 3 must both be number or Vector2', 2)
    end
    expect(4, x2, 'number')
    expect(5, y2, 'number')
    ---@cast x1 number
    ---@cast y1 number

    x1, y1, x2, y2 = correctCords(x1, y1, x2, y2)

    for x = x1, x2 do
        self:setPixel(x, y1, ' ', nil, color)
        self:setPixel(x, y2, ' ', nil, color)
    end
    for y = y1, y2 do
        self:setPixel(x1, y, ' ', nil, color)
        self:setPixel(x2, y, ' ', nil, color)
    end
end

---Draw a filled rectangle
---@param color string|color Color
---@param x1 number|Vector2
---@param y1 number|Vector2
---@param x2 number
---@param y2 number
---@overload fun(self: FrameBuffer, color: string, x1: number, y1: number, x2: number, y2: number)
---@overload fun(self: FrameBuffer, color: string, p1: Vector2, p2: Vector2)
function FrameBuffer:drawRectFilled(color, x1, y1, x2, y2)
    expect(1, color, 'string', 'number')
    if type(color) == 'number' then
        color = colors.toBlit(color)
    end
    expect(2, x1, 'number', 'Vector2')
    expect(3, y1, 'number', 'Vector2')
    if Vector2.isValid(x1) and Vector2.isValid(y1) then
        ---@cast x1 Vector2
        ---@cast y1 Vector2
        x2 = y1.x
        y2 = y1.y

        y1 = x1.y
        x1 = x1.x
    elseif Vector2.isValid(x1) or Vector2.isValid(y1) then
        error('Arguments 2 and 3 must both be number or Vector2', 2)
    end
    expect(4, x2, 'number')
    expect(5, y2, 'number')
    ---@cast x1 number
    ---@cast y1 number
    
    x1, y1, x2, y2 = correctCords(x1, y1, x2, y2)

    for x = x1, x2 do
        for y = y1, y2 do
            self:setPixel(x, y, ' ', nil, color)
        end
    end
end

---Draw a polygon
---@param color string|color Color
---@param points Vector2[] List of vertices
function FrameBuffer:drawPolygon(color, points)
    expect(1, color, 'string', 'number')
    if type(color) == 'number' then
        color = colors.toBlit(color)
    end
    ---@cast color string
    expect(2, points, 'table')
    local lp = points[#points]
    for i = 1, #points do
        local p = points[i]
        self:drawLine(color, lp, p)
        lp = p
    end
end

---@param x number
---@param y number
---@param points Vector2[]
---@return boolean
local function isInPoly(x, y, points)
    local c = false
    for i=2,#points do
        local a = points[i]
        local b = points[i - 1]
        if x == a.x and y == a.y then
            return true
        elseif (a.y > y) ~= (b.y > y) then
            local slope = (x - a.x) * (b.y - a.y) - (b.x - a.x) * (y - a.y)
            if slope == 0 then
                return true
            elseif (slope < 0) ~= (b.y < a.y) then
                c = not c
            end
        end
    end
    return c
end

---Draw a filled polygon
---@param color string|color Color
---@param points Vector2[] List of vertices
function FrameBuffer:drawPolygonFilled(color, points)
    expect(1, color, 'string', 'number')
    if type(color) == 'number' then
        color = colors.toBlit(color)
    end
    expect(2, points, 'table')
    local minX, minY = points[1].x, points[1].y
    local maxX, maxY = points[1].x, points[1].y

    for i = 1, #points do
        local p = points[i]
        if p.x < minX then
            minX = p.x
        elseif p.x > maxX then
            maxX = p.x
        end
        if p.y < minY then
            minY = p.y
        elseif p.y > maxY then
            maxY = p.y
        end
    end

    for x=minX,maxX do
        for y=minY,maxY do
            if isInPoly(x,y,points) then
                self:setPixel(x,y,' ',nil,color)
            end
        end
    end
end

---Sample the frame buffer getting the current text, text color, and back color
---@param x integer x position to sample
---@param y integer y position to sample
---@return string text
---@return string textColor
---@return string backColor
function FrameBuffer:sample(x, y)
    expect(1, x, 'number')
    expect(2, x, 'number')
    x = math.floor(x)
    y = math.floor(y)
    if 1 > x or x > self.width or 1 > y or y > self.height then
        return '', ' ', ' '
    end
    return self.text[y][x], self.textColor[y][x], self.backColor[y][x]
end

---Render a row of the frame buffer for use in a `blit` function
---@param y integer Y position in buffer
---@return string text
---@return string textColor
---@return string backColor
function FrameBuffer:render(y)
    expect(1, y, 'number')
    local text = self.__rowCache[1][y]
    if not text then
        text = table.concat(self.text[y])
        self.__rowCache[1][y] = text
    end
    local textColor = self.__rowCache[2][y]
    if not textColor then
        textColor = table.concat(self.textColor[y])
        self.__rowCache[2][y] = textColor
    end
    local backColor = self.__rowCache[3][y]
    if not backColor then
        backColor = table.concat(self.backColor[y])
        self.__rowCache[3][y] = backColor
    end
    return text, textColor, backColor
end

---Debug print for frame buffer
---@param log Logger? *(Optional)* Logger to print to instead of using `print()`
function FrameBuffer:print(log)
    local f = print
    for y = 1, self.height do
        local lT = ''
        local lTC = ''
        local lBC = ''
        for x = 1, self.width do
            local t, tC, bC = self:sample(x, y)
            if t == '' then t = ' ' end
            lT = lT .. t
            lTC = lTC .. tC
            lBC = lBC .. bC
        end
        if log then
            log:info(lT .. '|' .. lTC .. '|' .. lBC)
        else
            print(lT .. '|' .. lTC .. '|' .. lBC)
        end
    end
end

---Compare row of this frame buffer to another
---@param y integer Y position of row to compare
---@param other FrameBuffer Buffer to compare against
---@return boolean different
function FrameBuffer:compare(y, other)
    if not other then
        return true
    end
    local sT, sTC, sBC = self:render(y)
    local oT, oTC, oBC = other:render(y)
    return sT ~= oT or sTC ~= oTC or sBC ~= oBC
end

---Draw a frame buffer onto this frame buffer
---@param x number
---@param y number
---@param buffer FrameBuffer
---@param xOff number?
---@param yOff number?
---@param x2 number?
---@param y2 number?
function FrameBuffer:draw(x, y, buffer, xOff, yOff, x2, y2)
    expect(1, x, 'number')
    expect(2, y, 'number')
    expect(3, buffer, 'FrameBuffer')
    if x > self.width or y > self.height then
        return
    elseif x + buffer.width < 1 or y + buffer.height < 1 then
        return
    end

    xOff = (xOff or 1) - 1
    yOff = (yOff or 1) - 1
    x2 = x2 or buffer.width
    y2 = y2 or buffer.height
    local minX = math.max(x, 1)
    local maxX = math.min(x + x2, self.width)
    local minY = math.max(y, 1)
    local maxY = math.min(y + y2, self.height)
    
    for py=minY,maxY do
        for px = minX, maxX do
            local t, tC, bC = buffer:sample(px - x + 1 + xOff, py - y + yOff + 1)---@type string?, string?, string?
            if t == '' then t = nil end
            if tC == ' ' then tC = nil end
            if bC == ' ' then bC = nil end
            self:setPixel(px, py, t, tC, bC)
        end
    end
end