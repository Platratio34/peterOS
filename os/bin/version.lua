local vf = fs.open("/version.txt", "r")
if vf == nil then
    printError('Error loading version file')
    return
end
local line = vf.readLine()
print(line)
vf.close()