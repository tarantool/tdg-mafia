local game = require('game')

return {
    call = function(args)
        local id = args['id']
        return game.get_alive(id)
    end
}
