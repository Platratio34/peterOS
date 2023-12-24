local rttp = pos.require("rttp")
local server = rttp.server

server.setup("top", "test.com")

local runing = true

while runing do
    local msg = server.waitForMsg()
    -- print("MSG: {"..msg.origin..", "..msg.path..", "..msg.method..", '"..msg.body.."'}")
    if msg.path == "" then
        server.reply(msg, 200, "Hello world", {contentType="text/plain"})
    elseif msg.path == "/test" then
        local page = {
            {type="TEXT", x=2, y=1, text="Hello World", color=colors.lime},
            {type="TEXT", x=52-13, y=18, text="Made By Peter", color=colors.gray},
            {type="LINK", x=1, y=3, text="Page 2", href="/page2"}
        }
        server.reply(msg, 200, page, {contentType="table/rtml"})
    elseif msg.path == "/page2" then
        local page = {
            {type="TEXT", x=2, y=1, text="Goodby World", color=colors.red},
            {type="TEXT", x=52-13, y=18, text="Made By Peter", color=colors.gray},
            {type="LINK", x=1, y=3, text="Page 1", href="/test"}
        }
        server.reply(msg, 200, page, {contentType="table/rtml"})
    else
        server.reply(msg, 404, "Page not found", {contentType="text/plain"})
    end
end