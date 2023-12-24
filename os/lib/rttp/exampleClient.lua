local rttp = pos.require("rttp")
local client = rttp.client

local args = {...}

client.setup("top")

print("sending msg")
local domain = "test.com"
local path = ""
if #args == 1 then
    path = args[1]
end
local msg = client.getSync(domain, path)

if msg == nil then
    print("Somthing went wrong")
    return
end

if msg.code == 200 then
    print("Response: "..msg.body)
else
    print("RTTP error: "..msg.code.." - "..msg.body)
end