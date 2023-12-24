local rttp = pos.require("rttp")
local server = rttp.server

server.setup("top", "test.com")

local runing = true

while runing do
    local msg = server.waitForMsg()
    print("MSG: {"..msg.origin..", "..msg.path..", "..msg.method..", '"..msg.body.."'}")
    if msg.path == "" then
        server.reply(msg, 200, "Hello world", {})
    elseif msg.path == "/test" then
        local page = {
            {type="TEXT", x=0, y=0, text="Hello World"}
        }
        server.reply(msg, 200, page, {})
    else
        server.reply(msg, 404, "Page not found", {})
    end
end