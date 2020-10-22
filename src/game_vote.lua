local game = require('game')

return {
    call = function(args)
        return game.vote(g.id)
    end
}
