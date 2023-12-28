local clParse = {}
_G.pos.clParse = clParse

---@class Parser Command line parser utility
---@field flags table<string,CLFlag> Table of command line flags
local Parser = {
    flags = {}
}

---Create a new parser
---@return Parser
function pos.Parser()
    local o = {}
    setmetatable(o, { __index = Parser })
    return o
end

function Parser:parse(args)
    local cFlags = {}
    local cArgs = {}

    local temp = nil

    for _,arg in pairs(args) do
        if temp then
            if arg:sub(-1) == '"' then
                table.insert(cArgs,temp..arg:sub(1,-2))
                temp = nil
            else
                temp = temp .. arg
            end
        elseif arg:sub(1, 1) == '-' then
            local name = arg:sub(2)
            local val = true ---@type any
            if arg:cont('=') then
                local i = arg:find('=')
                name = arg:sub(2, i - 1)
                val = arg:sub(i + 1)
                if val == 'true' then
                    val = true
                elseif val == 'false' then
                    val = false
                elseif tonumber(val) then
                    val = tonumber(val)
                end
            end
            if self.flags[name] then
                name = self.flags[name].name
            end
            cFlags[name] = val
        elseif arg:sub(1,1) == '"' then
            temp = arg:sub(2)
        else
            table.insert(cArgs,arg)
        end
    end

    return cArgs, cFlags
end

function Parser:addFlag(name, short)
    local flag = {
        name = name,
        short = short
    }
    self.flags[name] = flag
    self.flags[short] = flag
end

---@class CLFlag
---@field name string
---@field short nil|string