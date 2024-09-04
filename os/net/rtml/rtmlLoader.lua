---@module 'os.net.rtml.rtmlLoader'

local xml = pos.require('xml')

pos.require('net.rtml')
local loader = {}

---Load an RTML file by filename
---@param filename string Path to file to load and parse
---@return table? rtml RTML as lua object OR `nil` if it could not be parsed
function loader.loadFile(filename)
    local f = fs.open(filename, 'r')
    if not f then
        error("Unable to open file", 2)
    end
    local rtml = loader.load(f.readAll())
    f.close()
    return rtml
end

---Get XML tag name and attributes
---@param line string Line to parse for XML tag
---@return nil|string name Name of the tag
---@return {string: any}? attributes Attribute table of tag (will be `nil` if tag is closing tag)
---@return boolean? closingTag If the tag is self closing or a closing tag
---@return string? line Remaining portion of line after XML tag
function loader.parseTag(line)
    local _, sI, name, nameEnder = line:find('%s*<(%a+)%s*(/?>?)%s*')
    if not sI then
        local _, tagEnd, tagName = line:find('%s*</(%a+)%s*>%s*')
        if tagName then
            return tagName, nil, true, line:sub(tagEnd+1)
        end
        return nil
    end
    if nameEnder == '>' or nameEnder == '/>' then
        return name, {}, nameEnder == '/>', line:sub(sI+1)
    end
    local attributes = {}
    while sI < #line do
        local atrNameEnd, valStart, atrName, nxt = line:find('%s*(%a+)%s*=%s*(.)', sI)
        if not atrNameEnd or not valStart then
            return nil
        end
        if nxt == '"' then
            local valEnd, breakEnd, valStr, valEnder = line:find('%s*"([^"]*)"%s*(/?[,>])%s*',valStart)
            if not valEnd or not breakEnd then
                return nil
            end
            attributes[atrName] = valStr
            if valEnder == '>' or valEnder == '/>' then
                return name, attributes, valEnder == '/>', line:sub(breakEnd+1)
            else
                sI = breakEnd
            end
        else
            local valEnd, breakEnd, valStr, valEnder = line:find('%s*([^,>]+)%s*(/?[,>])%s*', valStart)
            if not valEnd or not breakEnd then
                return nil
            end
            attributes[atrName] = textutils.unserialise(valStr)
            if valEnder == '>' or valEnder == '/>' then
                return name, attributes, valEnder == '/>', line:sub(breakEnd+1)
            else
                sI = breakEnd
            end
        end
    end
    return name, attributes, false, ""
end

---Load rtml from plaintext XML in version 1
---@param lines string
local function loadV1(rtml, lines)
    local parentTree = { {} }
    
    local nextScreenLine = 1

    local inXml = xml.parse(lines) ---@type XMLElement
    for i=1,#inXml.children do
        local c1 = inXml.children[i]
        if c1.name == 'RTML' then
            -- this was already processed
        elseif c1.name == 'body' then
            for j = 1, #c1.children do
                local c2 = c1.children[j]
                if c2.name == 'text' then
                    local el = c2.attributes --[[@as RTMLElement]] or {}
                    el.type = net.rtml.TYPE_TEXT
                    if not el.x then
                        el.x = 1
                    end
                    if not el.y then
                        el.y = nextScreenLine
                        nextScreenLine = nextScreenLine + 1
                    else
                        nextScreenLine = math.max(nextScreenLine, el.y + 1)
                    end
                    el.text = c2.inner
                    table.insert(rtml, el)
                elseif c2.name == 'link' then
                    local el = c2.attributes --[[@as RTMLElement]] or {}
                    el.type = net.rtml.TYPE_LINK
                    if not el.x then
                        el.x = 1
                    end
                    if not el.y then
                        el.y = nextScreenLine
                        nextScreenLine = nextScreenLine + 1
                    else
                        nextScreenLine = math.max(nextScreenLine, el.y + 1)
                    end
                    el.text = c2.inner
                    table.insert(rtml, el)
                elseif c2.name == 'dom-link' then
                    local el = c2.attributes --[[@as RTMLElement]] or {}
                    el.type = net.rtml.TYPE_DOM_LINK
                    if not el.x then
                        el.x = 1
                    end
                    if not el.y then
                        el.y = nextScreenLine
                        nextScreenLine = nextScreenLine + 1
                    else
                        nextScreenLine = math.max(nextScreenLine, el.y + 1)
                    end
                    table.insert(rtml, el)
                elseif c2.name == 'button' then
                    local el = c2.attributes --[[@as RTMLElement]] or {}
                    el.type = net.rtml.TYPE_BUTTON
                    if not el.x then
                        el.x = 1
                    end
                    if not el.y then
                        el.y = nextScreenLine
                        nextScreenLine = nextScreenLine + 1
                    else
                        nextScreenLine = math.max(nextScreenLine, el.y + 1)
                    end
                    table.insert(rtml, el)
                elseif c2.name == 'input' then
                    if not c2.selfClosing then
                        error('Malformed RTML, `input` tags must be self closing', 2)
                    end
                    local el = c2.attributes --[[@as RTMLElement]] or {}
                    el.type = net.rtml.TYPE_BUTTON
                    if not el.x then
                        el.x = 1
                    end
                    if not el.y then
                        el.y = nextScreenLine
                        nextScreenLine = nextScreenLine + 1
                    else
                        nextScreenLine = math.max(nextScreenLine, el.y + 1)
                    end
                    table.insert(rtml, el)
                end
            end
        else
            error(('Unknown tag `%s`'):format(c1.name), 2)
        end
    end
end

---Load rtml from plaintext lua object or XML
---@param file string File as string to parse
---@return table? rtml RTML as lua object OR `nil` if it could not be parsed
function loader.load(file)
    if #file < 6 then return nil end
    if file:sub(1, 5) == '<RTML' then
        local rtml = {}
        local rtmlTag = xml.parseForElement(file)
        rtml.header = rtmlTag.attributes or { version = 1 }
        if rtml.header.version == 1 then
            loadV1(rtml, file)
        else
            error(("Unknown RTML file version. Valid versions: 1, was %s"):format(textutils.serialise(rtml.header.version)), 2)
        end
        return rtml
    else
        return textutils.unserialise(file)
    end
end

return loader