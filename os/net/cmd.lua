local args = { ... }

if args[1] == 'update' then
    shell.run('/os/net/netUpdate.lua', args[2])
    return
elseif args[1] == 'ip' then
    if net.getIP() < 0 then
        print('No IP yet')
        return
    end
    if (not args[2]) or args[2] == '' or args[2] == '-4' then
        print(net.ipFormat(net.getIP()))
        return
    end
    print('Unknown IP format')
    return
elseif args[1] == 'help' then
    print("net update - Update the net package")
    print("net ip - Get current IP address")
    return
end

print('Unknown operation')