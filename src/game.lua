local repository = require('repository')
local json = require('json')
local log = require('log')

local function append_table(where, from)
    for _, item in pairs(from) do
        table.insert(where, item)
    end
    return where
end

local function has_value(array, value)
    if not array then
        return false
    end

    for _, v in ipairs(array) do
        if v == value then
            return true
        end
    end

    return false
end


local function get_profiles(ids)
    local result = {}
    for _, id in ipairs(ids) do
        local profile, err = repository.get('Profile', 'id', id)
        if err ~= nil then return nil, err end

        table.insert(result, profile[1])
    end

    return result
end

local function get_participants(game) return get_profiles(game.participant_ids) end
local function get_mafia(game) return get_profiles(game.mafia_ids) end

local function get_rounds(game_id)
    local rounds = {}

    local after = nil
    while true do
        local res, err = repository.find('Round', {{'$game_id', '==', game_id}}, {after=after})
        if err ~= nil then return nil, err end
        if #res == 0 then break end

        append_table(rounds, res)
        after = res[#res].cursor
    end

    return rounds
end


local function get_votes(game_id, round_id)
    local votes = {}

    local after = nil

    while true do
        local res, err = repository.find('Vote', {{'$game_id', '==', game_id}, {'$round_id', '==', round_id}}, {after=after})
        if err ~= nil then return nil, err end
        if #res == 0 then break end

        append_table(votes, res)
        after = res[#res].cursor
    end

    return votes
end

local function get_round(game_id, round_id)
    local round, err = repository.get('Round', 'primary', {game_id, round_id})
    if err ~= nil then return nil, err end

    return round[1]
end

local function get_game(game_id)
    local game, err = repository.get('Game', 'id', game_id)
    if err ~= nil then return nil, err end

    return game[1]
end


local function get_last_complete_round(game_id)
    local rounds, err = get_rounds(game_id)

    log.error("rounds: %s", json.encode(rounds))

    if err ~= nil then return nil, err end
    if rounds == nil then return nil end

    for i=#rounds,1,-1 do
        if rounds[i].complete == true then
            return rounds[i]
        end
    end

    return nil
end

local function get_current_round(game_id)
    local rounds, err = get_rounds(game_id)

    log.error("rounds: %s", json.encode(rounds))

    if err ~= nil then return nil, err end
    if rounds == nil or #rounds == 0 then return nil end

    return rounds[#rounds]
end


local function get_alive(game_id)
    log.error(game_id)
    local game, err = repository.get('Game', 'id', game_id)
    if err ~= nil then return nil, err end

    local round, err = get_last_complete_round(game_id)
    if err ~= nil then return nil, err end

    if round == nil then
        return game[1].participant_ids
    end

    local res = {}

    for _, id in ipairs(round.alive_ids) do
        local profile, err = repository.get('Profile', 'id', id)
        if err ~= nil then return nil, err end
        table.insert(res, profile[1])
    end

    return res
end

local function round_get_alive(round)
    local res = {}

    for _, id in ipairs(round.alive_ids or {}) do
        local profile, err = repository.get('Profile', 'id', id)
        if err ~= nil then return nil, err end
        table.insert(res, profile[1])
    end

    return res
end

local function calculate_round(game_id, round_id)
    local round, err = get_round(game_id, round_id)
    if err ~= nil then return nil, err end

    log.error("round: %s", json.encode(round))

    local game, err = get_game(round.game_id)
    if err ~= nil then return nil, err end

    if round.complete then
        return round.alive_ids
    end

    local last_round, err = get_last_complete_round(round.game_id)
    if err ~= nil then return nil, err end

    local alive = {}

    for _, id in ipairs(last_round.alive_ids) do
        alive[id] = true
    end

    local participants = {}

    if round.round_type == 'Night' then
        for _, id in ipairs(game.mafia_ids) do
            if has_value(last_round.alive_ids, id) then
                table.insert(participants, id)
            end
        end
    else
        participants = last_round.alive_ids
    end

    local alive = {}

    for _, id in ipairs(last_round.alive_ids) do
        alive[id] = 0
    end

    log.error("participants: %s", json.encode(participants))

    local votes, err = get_votes(round.game_id, round.id)
    if err ~= nil then return nil, err end

    if #votes < #participants then
        log.error("votes: %s, participants: %s", #votes, json.encode(participants))
        return nil
    end

    for _, vote in ipairs(votes) do
        alive[vote.target_id] = alive[vote.target_id] + 1
    end

    local killed = nil

    for _, id in ipairs(last_round.alive_ids) do
        if alive[id] > #participants/2 then
            killed = id
        end
    end

    if killed == nil then
        return nil
    end

    local result = {}

    for _, id in ipairs(last_round.alive_ids) do
        if id ~= killed then
            table.insert(result, id)
        end
    end

    return result
end

local function is_mafia_dead(participant_ids, mafia_ids, alive_ids)
    for _, id in ipairs(mafia_ids) do
        if has_value(alive_ids, id) then
            return false
        end
    end
    return true
end

local function is_citizens_dead(participant_ids, mafia_ids, alive_ids)
    for _, id in ipairs(participant_ids) do
        if has_value(alive_ids, id) and not has_value(mafia_ids, id) then
            return false
        end
    end
    return true
end

local function end_round(game_id)
    local round, err = get_current_round(game_id)
    if err ~= nil then return nil, err end

    local game, err = get_game(game_id)
    if err ~= nil then return nil, err end

    if round.complete == true then
        log.error('!!!!!!!!!!!!!!!!!!!!!')
        log.error('game: %s', json.encode(game))

        return game.complete
    end

    local alive_ids, err = calculate_round(game_id, round.id)
    if err ~= nil then return nil, err end

    if alive_ids == nil then
        log.error('!!!!!!!!!!!!!!!!!!!!!1')
        return nil
    end

    round.complete = true
    round.alive_ids = alive_ids
    round.cursor = nil
    round.version = nil

    local res, err = repository.put('Round', round)
    if err ~= nil then return nil, err end

    local citizens_dead = is_citizens_dead(game.participant_ids, game.mafia_ids, alive_ids)
    local mafia_dead = is_mafia_dead(game.participant_ids, game.mafia_ids, alive_ids)

    if citizens_dead or mafia_dead then
        game.complete = true
        game.cursor = nil
        game.version = nil

        if citizens_dead then
            game.who_won = 'Mafia'
        else
            game.who_won = 'Citizens'
        end

        local res, err = repository.put('Game', game)
        if err ~= nil then return nil, err end

        return true
    end

    return false
end

local function new_round(game_id)
    local round, err = get_current_round(game_id)
    if err ~= nil then return nil, err end

    local game, err = get_game(game_id)
    if err ~= nil then return nil, err end

    if game.complete then
        return true
    end

    if round == nil then
        local res, err = repository.put('Round', {
                                            game_id = game.id,
                                            id = 1,
                                            round_type = 'Night',
                                            complete = false
        })
        if err ~= nil then return nil, err end

    end

    if round.complete ~= true then
        return false
    end

    local round_type = 'Day'

    if round.type == 'Day' then
        round_type = 'Night'
    end

    local res, err = repository.put('Round', {
                                        id = round.id + 1,
                                        game_id = game.id,
                                        round_type = round_type,
                                        complete = false
    })
    if err ~= nil then return nil, err end

    return false
end

local function random_shuffle(list)
    for i = #list, 2, -1 do
        local j = math.random(i)
        list[i], list[j] = list[j], list[i]
    end
end

local function new_game(participant_ids)
    if #participant_ids < 5 then
        return nil, "Need at least 5 players"
    end

    random_shuffle(participant_ids)

    local res, err = repository.put('Game', {
         participant_ids = participant_ids,
         mafia_ids = {participant_ids[1], participant_ids[2]},
         complete = false
    })
    if err ~= nil then return nil, err end

    return res[1].id
end

local function vote(game_id, target, action)
    local vote, err = repository.get('Vote', 'primary', id)
    if err ~= nil then return nil, err end


end


return {
    get_participants = get_participants,
    get_mafia = get_mafia,
    get_alive = get_alive,
    round_get_alive = round_get_alive,
    calculate_round = calculate_round,
    end_round = end_round,
    new_round = new_round,
    new_game = new_game
}
