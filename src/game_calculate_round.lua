local game = require('game')

return {
    call = function(args)
        local id = args['id']
        return game.calculate_round(id)
    end
}
