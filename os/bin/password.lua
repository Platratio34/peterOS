print("Chaning SuperUser password:")

write("Current password: ")
local cp = read("")
write("New password: ")
local np1 = read("")
write("Repeate new password: ")
local np2 = read("")

if not np1 == np2 then
    print("Password must match")
    return
end

user.setSuPass(cp, np1)
return