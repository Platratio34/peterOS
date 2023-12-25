if _G.user and not user.isSu() then
    shell.run("su")
end
if _G.user and not user.isSu() then
    printError('Must have root access to install')
    return
end

local cB = '?'..os.epoch('utc') % 60000
local baseURL = 'https://raw.githubusercontent.com/Platratio34/peterOS/master/os/net/'
local fileNames = {
    'init.lua',
    'encrypt.lua',
    'nat.lua',
    'dhcp.lua'
}
for _, fileName in pairs(fileNames) do
    local rsp, msg = http.get(baseURL .. fileName.. cB)
    if rsp == nil then
        printError(fileName .. " | HTTP error: " .. msg)
        print("Terminating update")
        return
    end
    if rsp.getResponseCode() ~= 200 then
        printError(fileName .. " | HTTP response code " .. rsp.getResponseCode() .. " msg: " .. rsp.readAll())
        print("Terminating update")
        return
    end

    local f = fs.open('/os/net/' .. fileName, 'w')
    if not f then
        printError('Could not open file ' .. fileName .. ' for write')
        return
    end
    f.write(rsp.readAll())
    f.close()
end
print('Updated net package')
os.reboot()