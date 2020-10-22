local game = require('game')

return {
    call = function(args)
        local id = args['id']
        return game.new_round(id)
    end
}
