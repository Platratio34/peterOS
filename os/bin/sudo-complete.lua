local completion = require "cc.shell.completion"
local complete = completion.build(
    {completion.programWithArgs, 2, many=true}
)

return { complete=complete }