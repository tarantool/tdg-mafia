local game = require('game')

return {
    call = function(g)
        return game.get_phase(g.id)
    end
}
