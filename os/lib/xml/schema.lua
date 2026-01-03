---@class XMLSchema
---@field elements { [string]: XMLSchema.Element }
local XMLSchema = {}
local XMLSchemaMT = {
    __index = XMLSchema
}

---@class XMLSchema.Element
---@field attributes { [string]: XMLSchema.Attribute } Table of valid attributes
---@field parent string? Name of element this element inherits from

---@class XMLSchema.Attribute
---@field type string Type of attribute value
---@field optional boolean?

---Parse an object for XML schema information
---@param schemaObj table Object loaded from JSON or LUA
---@return XMLSchema schema Schema object for verifying XML against
function XMLSchema.parse(schemaObj)
    local schema = XMLSchema.new()

    for name, element in pairs(schemaObj) do
        local attributes = {} ---@type { [string]: XMLSchema.Attribute }
        local parent = nil
        if #element >= 1 then
            parent = element[1]
            element = element[2]
        end
        if element and type(element) == 'table' then
            ---@cast element { [string]: string }
            for atrName, atrType in pairs(element) do
                attributes[atrName] = XMLSchema.makeAttribute(atrType)
            end
        end
        schema:addElement(name, attributes, parent)
    end

    return schema
end

---Create a new XML Schema object
---@return XMLSchema schema
function XMLSchema.new()
    local o = {}
    setmetatable(o, XMLSchemaMT) ---@cast o XMLSchema
    o:__init__()
    return o
end

---Initializes the schema object
---@package
function XMLSchema:__init__()
    self.elements = {
        ["_xml_"] = {
            attributes = {},
            parent = nil
        }
    }
end

---Add an element to this schema
---@param name string
---@param attributes { [string]: XMLSchema.Attribute }
---@param parent string?
function XMLSchema:addElement(name, attributes, parent)
    self.elements[name] = {
        attributes = attributes,
        parent = parent
    }
end

---Make the provided type string into an XMLSchema.Attribute object
---@param typeStr string
---@return XMLSchema.Attribute
function XMLSchema.makeAttribute(typeStr)
    local atr = { type = typeStr } ---@type XMLSchema.Attribute
    if typeStr:ends('?') then
        atr.optional = true
        atr.type = typeStr:sub(1, -2)
    end
    return atr
end

---Check if the provided XMLElement is valid according to this schema
---**DOES NOT CHECK CHILDREN**
---@param element XMLElement Element to check
---@return boolean valid If the element was valid
---@return string error Schema error **OR** `''`
function XMLSchema:checkElement(element)
    local elType = self.elements[element.name]
    if not elType then
        return false, 'unknown element `'..element.name..'`'
    end
    return self:__checkElement(element, elType)
end

---**INTERNAL** check element function
---@package
---@param element XMLElement Element to check
---@param elType XMLSchema.Element Schema element to check against
---@return boolean valid If the element was valid
---@return string error Schema error **OR** `''`
function XMLSchema:__checkElement(element, elType)
    for atrName, atr in pairs(elType.attributes) do
        if not atr.optional then
            if not element.attributes[atrName] then
                return false, ('missing required attribute `%s`'):format(atrName)
            end
        else
            local atrType = type(element.attributes[atrName])
            if atrType ~= "nil" and atrType ~= atr.type then
                local v = element.attributes[atrName]
                if atrType == 'string' and atr.type == 'number' then
                    if not tonumber(v) then
                        return false, ('attribute `%s` must be %s, was %s, and could not be converted'):format(atrName, atr.type .. (atr.optional and '?' or ''), atrType)
                    end
                elseif atrType == 'string' and atr.type == 'boolean' then
                    if v ~= 'false' and v ~= 'true' then
                        return false, ('attribute `%s` must be %s, was %s, and could not be converted'):format(atrName, atr.type .. (atr.optional and '?' or ''), atrType)
                    end
                else
                    return false, ('attribute `%s` must be %s, was %s'):format(atrName, atr.type .. (atr.optional and '?' or ''), atrType)
                end
            end
        end
    end
    if elType.parent then
        return XMLSchema:__checkElement(element, self.elements[elType.parent])
    end
    return true, ''
end

---Check if the provided XMLElement is valid according to this schema **AND** Fixes string values to correct type
---**DOES NOT CHECK CHILDREN**
---@param element XMLElement Element to check
---@return boolean valid If the element was valid
---@return string error Schema error **OR** `''`
function XMLSchema:checkElementAndFix(element)
    local elType = self.elements[element.name]
    if not elType then
        return false, 'unknown element: `'..element.name..'`'
    end
    return self:__checkElementAndFix(element, elType)
end

---**INTERNAL** check element function that fixes value types
---@package
---@param element XMLElement Element to check
---@param elType XMLSchema.Element Schema element to check against
---@return boolean valid If the element was valid
---@return string error Schema error **OR** `''`
function XMLSchema:__checkElementAndFix(element, elType)
    for atrName, atr in pairs(elType.attributes) do
        if not atr.optional and not element.attributes[atrName] then
            return false, ('missing required attribute `%s` in element `%s`'):format(atrName, element.name)
        else
            local atrValue = element.attributes[atrName]
            local atrType = type(atrValue)
            if(atrType == "nil") then

            elseif atrType == 'string' and atr.type ~= 'string' then
                if atr.type == 'number' then
                    atrValue = tonumber(atrValue)
                    if not atrValue then
                        return false,
                        ('attribute `%s` in `%s` must be %s, was %s'):format(atrName, element.name,
                                atr.type .. (atr.optional and '?' or ''), atrType)
                    end
                elseif atr.type == 'boolean' then
                    if atrValue == 'true' then
                        atrValue = true
                    elseif atrValue == 'false' then
                        atrValue = false
                    else
                        return false,
                            ('attribute `%s` in `%s` must be %s, was %s'):format(atrName, element.name,
                                atr.type .. (atr.optional and '?' or ''), atrType)
                    end
                else
                    return false,
                            ('attribute `%s` in `%s` must be %s, was %s'):format(atrName, element.name,
                                atr.type .. (atr.optional and '?' or ''), atrType)
                end
                element.attributes[atrName] = atrValue
            elseif atrType ~= atr.type then
                return false,
                            ('attribute `%s` in `%s` must be %s, was %s'):format(atrName, element.name,
                                atr.type .. (atr.optional and '?' or ''), atrType)
            end
        end
    end
    if elType.parent then
        return XMLSchema:__checkElementAndFix(element, self.elements[elType.parent])
    end
    return true, ''
end

return setmetatable({elements={}}, XMLSchemaMT)