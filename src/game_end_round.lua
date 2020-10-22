local game = require('game')

return {
    call = function(args)
        local id = args['id']
        return game.end_round(id)
    end
}
