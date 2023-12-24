local args = {...}

if #args==0 then
    printError("Must have a program")
    return
end

if args[1] == "-k" then
    user.sudo("")
    print("Sudo killed")
    return
end

write("Password: ")
local psw = read("")
print("")
--print(psw)
if user.sudo(psw) then
    local argStr = ""
    for i = 1, #args do
        if i > 1 then argStr = argStr .. " " end
        argStr = argStr .. args[i]
    end
    shell.run(argStr)
    user.sudo('')
else
    printError("Invalid Password")
end
