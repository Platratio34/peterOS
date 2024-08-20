pos.require("net.rttp")
local rtmlLoader = pos.require('os.net.rtml.rtmlLoader') ---@module 'os.net.rtml.rtmlLoader'

local serverCfgF = fs.open("/home/www/server.cfg", "r")
if serverCfgF ~= nil then
    local serverCfg = textutils.unserialise(serverCfgF.readAll())
    serverCfgF.close()

    rttp.handleMsg(function(method,head,body,msg)
        if method == "GET" then
            if head.path == "" then
                return 200, "none", "", {redirect="/"}
            elseif not (serverCfg.pages[head.path] == nil) then
                local f = fs.open("/home/www/" .. serverCfg.pages[head.path], "r")
                if not f then
                    return 500, 'text/plain', 'Could not read page from file'
                end
                local page = rtmlLoader.load(f.readAll())
                f.close()
                return 200, "table/rtml", page
            else
                return 404, "text/plain", "Page not found"
            end
        else
            return 404, "text/plain", "Invalid method, must be GET"
        end
    end)
else
    rttp.handleMsg(function(method, head, body, msg)
        print("Received RTTP request")
        print("- " .. rttp.stringMessage(msg))
        if method ~= "GET" then
            return rttp.responseCodes.methodNotAllowed, "text/plain", "Only GET is implemented on this server, can not use '"..method.."'"
        end
        if head.path == "" then
            return rttp.responseCodes.okay, "text/plain", "This is a simple RTTP server"
        else
            return rttp.responseCodes.notFound, "text/plain", "Path not found on server"
        end
        return rttp.responseCodes.internalServerError, "text/plain", "The server encountered an error processing the request"
    end)
end

net.setup()
rttp.registerHandler()
print("Starting RTTP server at "..net.ipFormat(net.getIP())..":10080")