-- src/states/PausedState.lua
local BaseState = require("src.states.BaseState")
local StateManager = require("src.states.StateManager")
local constants = require("src.constants")
local ResourceManager = require("src.managers.ResourceManager")

local PausedState = setmetatable({}, BaseState)
PausedState.__index = PausedState

function PausedState.new()
    return setmetatable({}, PausedState)
end

function PausedState:draw()
    -- 背景由 PlayingState 提供
end

function PausedState:drawUI(scale)
    scale = scale or 1
    love.graphics.setFont(ResourceManager.font)
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.rectangle("fill", 0, 0, constants.GAME_WIDTH * scale, constants.GAME_HEIGHT * scale)
    
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf("GAME PAUSED", 0, (constants.GAME_HEIGHT / 2 - 20) * scale, constants.GAME_WIDTH * scale, "center")
    love.graphics.printf("PRESS [P] TO RESUME", 0, (constants.GAME_HEIGHT / 2 + 10) * scale, constants.GAME_WIDTH * scale, "center")
end

function PausedState:keypressed(key, scancode)
    if scancode == "p" then
        StateManager.switch("playing")
    end
end

return PausedState
