---@package pos.gui
---@class ListField : UiElement Basic text input box
---@field scroll number Current scroll position
---@field private _elements UiElement[] List of all elements drawn inside the list field
---@field private __elementIndex number Index of last added element
---@field type string Override. UiElement type field: <code class=string>'ListField'</code>
local ListField = {
    scroll = 0,
    _elements = {},
    __elementIndex = 0,
    type = 'ListField'
}
setmetatable(ListField, { __index = pos.gui.mt.UiElement })

---Initializes the list field
---@param x number X position
---@param y number Y position
---@param w number Width
---@param h number Height
function ListField:__init__(x, y, w, h)
    self._elements = {}
    self.x = x
    self.y = y
    self.w = w
    self.h = h
end

---Override. Draws the list field and all sub elements
---@param window Window Window the list field is drawn in
function ListField:draw(window)
    local intWindow = {
        x = window.x + self.x - 1,
        y = window.y + self.y - 1 - self.scroll,
        w = self.w,
        h = self.h,
    }
    paintutils.drawFilledBox(window.x + self.x, window.y + self.y, self.w + window.x + self.x - 1, self.h + window.y + self.y - 1, self.bg)
    local y = 1
    for i = 0, self.__elementIndex do
        local el = self._elements[i]
        if el and el.visible then
            el.y = y
            if not ((el.y + el.h - 1 <= self.scroll) or (el.y > self.h + self.scroll --[[ and el.y + el.h - 1 > self.h + self.scroll]])) then
                el:draw(intWindow)
            end
            y = y + el.h
        end
    end
end
---Override. Processes <code>mouse_scroll</code> events for the list field
---@param event table Event table
---@param window Window The window the list field is processed in
function ListField:process(event, window)
    if event[1] == 'mouse_scroll' then
        local _, dir, x, y = unpack(event)
        x = x - window.x
        y = y - window.y
        if pos.gui.inBox(window, self.x, self.y, self.w, self.h, x, y) then
            self.scroll = self.scroll + dir
            local max = 0
            for _, el in pairs(self._elements) do
                max = math.max(max, el.y + el.h - 1)
            end
            max = math.max(0, max - self.h)
            if self.scroll < 0 then
                self.scroll = 0
            elseif self.scroll > max then
                self.scroll = max
            end
        end
    end
    local intWindow = {
        x = window.x + self.x - 1,
        y = window.y + self.y - self.scroll - 1,
        w = self.w,
        h = self.h,
    }
    -- pos.gui._log:debug(tostring(self._elements))
    local t = {}
    for i, el in pairs(self._elements) do
        t[i] = el
    end
    for _, el in pairs(t) do
        if el.visible then
            el:process(event, intWindow)
        end
    end
end

---Add a element to the list field
---@param element UiElement Element to add
---@return number index Element index in the list field
function ListField:addElement(element)
    local index = self.__elementIndex
    self._elements[index] = element
    self.__elementIndex = self.__elementIndex + 1
    return index
end
---Remove an element from the list field by index
---@param index number Index of element to remove
function ListField:removeElement(index)
    self._elements[index] = nil
end
---Clears all elements from list field. Next element will be id 0
function ListField:clearElements()
    self._elements = {}
    self.__elementIndex = 0
    self.scroll = 0
end

---Creates a scrollable list field
---@constructor ListField
---@param x number X coord
---@param y number Y Coord
---@param w number Width
---@param h number Height
---@return ListField listField
function pos.gui.ListField(x, y, w, h)
    local o = {}
    setmetatable(o, { __index = ListField })
    o:__init__(x,y,w,h)
    return o
end