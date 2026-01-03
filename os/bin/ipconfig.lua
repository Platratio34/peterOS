local args = {...}

if not net.isSetup() then
    print("Network module not setup up")
    return;
end

---@param interface NetInterface
local function printInterface(interface)
    print(interface.name..'    '..interface:getHWAddress())
    if( not interface:getIp() ) then
        return
    end
    print('  address: '..net.ipFormat(interface:getIp()))
    print('  mask: '..net.ipFormat(interface:getSubnetMask()))
    print('  modem: '..peripheral.getName(interface:getModem()))
end

for _,i in pairs(net.getInterfaces()) do
    printInterface(i)
    print()
end