---@class Parser Command line parser utility
---@field flags {string: CLFlag} Table of known command line flags
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

---Parse command line arguments. Pulls out flags and values, and respects quotation marks
---@param args string[] Command line arguments
---@return string[] arguments Arguments without flags
---@return {string: any} flags Table of flags found
function Parser:parse(args)
    local cFlags = {} ---@type {string: any}
    local cArgs = {} ---@type string[]

    local temp = nil

    for _,arg in pairs(args) do
        if temp then
            if arg:ends('"') then
                table.insert(cArgs,temp..arg:sub(1,-2))
                temp = nil
            else
                temp = temp .. arg
            end
        elseif arg:start('-') then
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
        elseif arg:start('"') then
            temp = arg:sub(2)
        else
            table.insert(cArgs,arg)
        end
    end

    return cArgs, cFlags
end

---Add a flag to the parser
---@param name string Flag name
---@param short? string Short name for flag
function Parser:addFlag(name, short)
    local flag = {
        name = name,
        short = short
    }
    self.flags[name] = flag
    if short then
        self.flags[short] = flag
    end
end

---@class CLFlag
---@field name string Flag full name
---@field short string? *(Optional)* Flag short name