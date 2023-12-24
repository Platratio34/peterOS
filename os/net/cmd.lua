local args = { ... }

if args[1] == 'update' then
    shell.run('/os/net/netUpdate.lua')
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
end

print('Unknown operation')