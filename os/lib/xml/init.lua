---@module 'xml'
local xml = {
    PARENT_ELEMENT_NAME = "_xml_",
    XMLSchema = dofile('/os/lib/xml/schema.lua') ---@type XMLSchema
}

---@class XMLElement XML element
---@field name string Name of the element
---@field attributes { [string]: any } Table of attributes
---@field children XMLElement[] List of children in order found
---@field inner string? Non-element text between opening and closing elements
---@field parent XMLElement? Parent of this element
---@field selfClosing boolean? If this element is self closing
---@field closing boolean? If this element is a closing element
local XMLElement = {}

local XMLElement_MT = {}

---Initialize this XML element
---@package
---@param name string? *(Optional)* Element name
function XMLElement:__init__(name)
    self.name = name or ""
    self.attributes = {}
    self.children = {}
end

---Add a child to this XML element. **Will set child's `parent` element**
---@param child XMLElement Child element to add
function XMLElement:addChild(child)
    table.insert(self.children, child)
    child.parent = self
end

---__index meta-method for XMLElement
---@param index any
---@return any
function XMLElement_MT:__index(index)
    if type(index) == 'string' then
        return XMLElement[index]
    end
    if type(index) == 'number' then
        return self.children[index]
    end
    return nil
end

---Parses a string for XML data
---@param str string String to parse
---@return XMLElement xml Parent XML element
function xml.parse(str)
    local xmlFile = xml.XMLElement(xml.PARENT_ELEMENT_NAME)
    local cElement = xmlFile ---@type XMLElement
    if str:find('^%s*<%?xml') then
        local _, headerEnd = str:find('%?>')
        if not headerEnd then
            error('Malformed XML: `xml` element opened but never closed', 2)
        end
        local _, versionEnd, version = str:find('%s+version="([^"]*)"%s*')
        if versionEnd and versionEnd < headerEnd then
            xmlFile.attributes['version'] = version
        end
        local _, encodingEnd, encoding = str:find('%s+encoding="([^"]*)"%s*')
        if encodingEnd and encodingEnd < headerEnd then
            xmlFile.attributes['encoding'] = encoding
        end
        str = str:sub(headerEnd+1)
    end
    while #str > 0 and (not str:find('^%s*$')) do
        if str:find('^%s*<!%-%-') then
            local _, commentEnd = str:find('%-%->')
            str = str:sub(commentEnd + 1)
        elseif str:find('^%s*<') then
            local element, remaining = xml.parseForElement(str)
            if element then
                str = remaining --[[@as string]]
                if element.closing then
                    if cElement.name ~= element.name then
                        error(
                        ('Malformed XML, unclosed element of type `%s` at `%s` trying to close element of type `%s`')
                        :format(cElement.name, str, element.name), 2)
                    end
                    cElement = cElement.parent--[[@as XMLElement]]
                else
                    cElement:addChild(element)
                    if not element.selfClosing then
                        cElement = element
                    end
                end
            end
        elseif cElement.name ~= xml.PARENT_ELEMENT_NAME then
            local _, _, inner, next = str:find('([^<]-)%s*(<.*)')
            if not inner then
                error(('Malformed XML, element of type %s was never closed at `%s`'):format(cElement.name, str), 2)
            end
            str = next
            cElement.inner = inner
        elseif not str:find('^%s*$') then
            error(('Malformed XML, found text outside of any element: `%s`...'):format(str:sub(1, 12)), 2)
        end
    end
    if cElement.name ~= xml.PARENT_ELEMENT_NAME then
        error(('Malformed XML, tag `%s` was never closed'):format(cElement.name), 2)
    end
    return xmlFile
end

---Parse a string for the next XML Element
---@param str string String to parse
---@return XMLElement? xmlElement XML element, if present
---@return string? remaining String after XML element (string includes respective closing element)
function xml.parseForElement(str)
    local element = xml.XMLElement()
    if str:find('^%s*</(%a+)%s*>') then
        local _, _, tagName, remaining2 = str:find('%s*</(%a+)%s*>(.*)')
        if (tagName == xml.PARENT_ELEMENT_NAME) then
            error(('Invalid XML Element name; cannot be `%s`'):format(xml.PARENT_ELEMENT_NAME), 2)
        end
        element.name = tagName
        element.closing = true
        return element, remaining2
    end
    local _, _, name, nameEnder, remaining = str:find('%s*<(%a+)%s*(/?>?)%s*(.*)')
    if (name == xml.PARENT_ELEMENT_NAME) then
        error(('Invalid XML Element name; cannot be `%s`'):format(xml.PARENT_ELEMENT_NAME), 2)
    end
    if not name then
        return nil
    end
    element.name = name
    _, _, remaining = remaining:find('(.-)%s*$')
    if nameEnder == '>' or nameEnder == '/>' then
        element.selfClosing = nameEnder == '/>'
        return element, remaining
    end
    while #remaining > 0 and (not remaining:find('^^%s*$'))do
        local atrNameEnd, valStart, atrName, nxt = remaining:find('%s*(%a+)%s*=%s*(.)')
        if not atrNameEnd or not valStart then
            return nil
        end
        remaining = remaining:sub(valStart)
        if nxt == '"' then
            local valEnd, breakEnd, valStr, valEnder, after = remaining:find('%s*"([^"]*)",?%s*(/?>?)%s*(.*)')
            if not valEnd or not breakEnd then
                return nil
            end
            element.attributes[atrName] = valStr
            element.selfClosing = valEnder == '/>'
            if valEnder == '>' or valEnder == '/>' then
                return element, after
            else
                remaining = after
            end
        else
            local valEnd, breakEnd, valStr, valEnder, after = remaining:find('%s*([^%s/>,]+),?%s*(/?>?)%s*(.*)')
            if not valEnd or not breakEnd then
                return nil
            end
            if valStr == 'true' then
                element.attributes[atrName] = true
            elseif valStr == 'false' then
                element.attributes[atrName] = false
            else
                local s = pcall(function() element.attributes[atrName] = tonumber(valStr) end)
                if not s then
                    error('Malformed XML, attribute value must be a number, `true`, `false`, or a `"` encapsulated string', 2)
                end
            end
            element.selfClosing = valEnder == '/>'
            if valEnder == '>' or valEnder == '/>' then
                return element, after
            else
                remaining = after
            end
        end
        _, _, remaining = remaining:find('%s*(.*)')
    end
    error(("How did we get here? (Contact developer) `%s`, `%s`"):format(str, remaining), 2)
end

---Check if this element (and all children) are valid according to the provided schema
---@param schema XMLSchema The schema to check with
---@return boolean valid If the element and children where valid
---@return string error Schema error **OR** `''`
function XMLElement:verify(schema)
    local v, e = schema:checkElement(self)
    if not v then
        return v, e
    end

    for _, el in pairs(self.children) do
        v, e = el:verify(schema)
        if not v then
            return v, e
        end
    end
    return true, ''
end

---Fixes this element (and all children) according to the provided schema
---@param schema XMLSchema The schema to check with
---@return boolean valid If the element and children where valid
---@return string error Schema error **OR** `''`
function XMLElement:fix(schema)
    local v, e = schema:checkElementAndFix(self)
    if not v then
        return v, e
    end
    
    for _, el in pairs(self.children) do
        v, e = el:fix(schema)
        if not v then
            return v, e
        end
    end
    return true, ''
end

---Create a new XMLElement
---@param name string? *(Optional)* Name of the XML element
---@return XMLElement xmlElement New XML element
function xml.XMLElement(name)
    local o = {}
    setmetatable(o, XMLElement_MT) ---@cast o XMLElement
    o:__init__(name)
    return o
end

---Convert an XMLElement to a string
---@param element XMLElement XML element to convert to a string
---@return string xmlElement The XML element as a string
function xml.xmlElementToString(element)
    local str = ('{ name:"%s", nChildren: %d, attributes:['):format(element.name, #element.children)
    local fA = true
    for name in pairs(element.attributes) do
        if not fA then
            str = str .. ', '
        end
        if type(element.attributes[name]) == 'string' then
            str = str .. ('%s:"%s"'):format(name, element.attributes[name])
        else
            str = str .. ('%s:%s'):format(name, tostring(element.attributes[name]))
        end
        fA = false
    end
    str = str .. ']'
    if element.inner then
        str = str .. (', inner="%s"'):format(element.inner)
    end
    if element.closing then
        str = str .. ', closing'
    end
    if element.selfClosing then
        str = str .. ', selfClosing'
    end
    return str .. ' }'
end
XMLElement_MT.__tostring = xml.xmlElementToString

return xml