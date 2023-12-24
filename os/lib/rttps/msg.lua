local msg = {
    type = "rttps", -- intersystem type code
    origin = 0, -- origin id
    host = "" or 0, -- hostname or ID
    path = "", -- path at host
    method = "", -- ["GET", "PUSH"]
    code = 0, -- [ 200="Okay", 404="Page Not Found", ... ] standatd http/https response codes
    body = { -- message body
        shared = 0, -- shared key
        data = "", -- encrypted body
    },
    header = {}, 
}

local c_data = { -- unecrypted body
    rttpsClientKey = {}, -- clients public key object (need for all requests)
    ... -- other data
}

local s_body_rttp = { -- body for server response to message via rttp with code 101 and headers { upgrade="rttps" }
    shared = 0, -- shared key for server public key
    public = 0, -- server public server
}