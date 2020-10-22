local uuid = require('uuid')

return {
    call = function()
        return uuid.str()
    end
}
