local completion = require "cc.shell.completion"
local complete = completion.build(
    { completion.choice, { "update", "install", "upgrade" } }
)

return { complete=complete }