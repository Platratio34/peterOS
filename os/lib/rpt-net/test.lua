local rtp = require(".os.lib.net.rtp")

rtp.setup("test1")

rtp.send("test2","POST","This is a test")

local msg = rtp.recive()

print(msg.msg)

rtp.cleanup()
