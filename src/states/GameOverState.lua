-- src/states/GameOverState.lua
local BaseState = require("src.states.BaseState")
local StateManager = require("src.states.StateManager")
local constants = require("src.constants")
local ResourceManager = require("src.managers.ResourceManager")

local GameOverState = setmetatable({}, BaseState)
GameOverState.__index = GameOverState

function GameOverState.new()
    local self = setmetatable({}, GameOverState)
    self.score = 0
    return self
end

function GameOverState:enter(params)
    self.score = params and params.score or 0
end

function GameOverState:draw()
end

function GameOverState:drawUI(scale)
    scale = scale or 1
    love.graphics.setFont(ResourceManager.font)
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.rectangle("fill", 0, 0, constants.GAME_WIDTH * scale, constants.GAME_HEIGHT * scale)
    
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf("GAME OVER", 0, (constants.GAME_HEIGHT / 2 - 40) * scale, constants.GAME_WIDTH * scale, "center")
    love.graphics.printf("SCORE: " .. self.score, 0, (constants.GAME_HEIGHT / 2 - 10) * scale, constants.GAME_WIDTH * scale, "center")
    love.graphics.printf("PRESS [ENTER] TO RESTART", 0, (constants.GAME_HEIGHT / 2 + 20) * scale, constants.GAME_WIDTH * scale, "center")
end

function GameOverState:keypressed(key, scancode)
    if scancode == "return" then
        StateManager.switch("title")
    end
end

return GameOverState
