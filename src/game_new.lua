local game = require('game')

return {
    call = function(args)
        local participant_ids = args['participant_ids']
        return game.new_game(participant_ids)
    end
}
