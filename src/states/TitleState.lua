-- src/states/TitleState.lua
local BaseState = require("src.states.BaseState")
local StateManager = require("src.states.StateManager")
local ResourceManager = require("src.managers.ResourceManager")
local constants = require("src.constants")

local TitleState = setmetatable({}, BaseState)
TitleState.__index = TitleState

function TitleState.new()
    return setmetatable({}, TitleState)
end

function TitleState:draw()
    -- 獲取實際尺寸與縮放已在 main.lua 處理，這裡只需繪製世界空間
end

function TitleState:drawUI(scale)
    scale = scale or 1
    love.graphics.setFont(ResourceManager.font)
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 0, 0, constants.GAME_WIDTH * scale, constants.GAME_HEIGHT * scale)
    
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf("TETRIS x BREAKOUT", 0, (constants.GAME_HEIGHT / 2 - 40) * scale, constants.GAME_WIDTH * scale, "center")
    love.graphics.printf("PRESS [ENTER] TO START", 0, (constants.GAME_HEIGHT / 2) * scale, constants.GAME_WIDTH * scale, "center")
end

function TitleState:keypressed(key, scancode)
    if scancode == "return" then
        ResourceManager.playSound("start")
        StateManager.switch("playing", {reset = true})
    end
end

return TitleState
