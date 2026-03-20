-- ===================================
-- 程式夥伴：Lua (LÖVE/Love2D) 混和模式遊戲 (重構後)
-- 模式：俄羅斯方塊 (Tetris) & 打磚塊 (Breakout)
-- ===================================

local constants = require("src.constants")
local StateManager = require("src.states.StateManager")
local ResourceManager = require("src.managers.ResourceManager")
local TitleState = require("src.states.TitleState")
local PlayingState = require("src.states.PlayingState")
local PausedState = require("src.states.PausedState")
local GameOverState = require("src.states.GameOverState")

function love.load()
    -- 初始化資源
    ResourceManager.load()
    
    -- 視窗設置
    love.window.setMode(constants.GAME_WIDTH, constants.GAME_HEIGHT, {
        resizable = false,
        minwidth = constants.GAME_WIDTH,
        minheight = constants.GAME_HEIGHT
    })
    love.window.setTitle("Tetris-Breakout Hybrid (Refactored)")
    
    -- 禁用 IME 干擾
    love.keyboard.setTextInput(false)
    
    -- 註冊狀態
    StateManager.register("title", TitleState.new())
    StateManager.register("playing", PlayingState.new())
    StateManager.register("paused", PausedState.new())
    StateManager.register("gameover", GameOverState.new())
    
    -- 初始狀態
    StateManager.switch("title")
end

function love.update(dt)
    StateManager.update(dt)
end

function love.draw()
    -- 計算縮放與置中 (Letterboxing)
    local actualWidth, actualHeight = love.graphics.getDimensions()
    local scaleX = actualWidth / constants.GAME_WIDTH
    local scaleY = actualHeight / constants.GAME_HEIGHT
    local scale = math.min(scaleX, scaleY)
    
    local offsetX = (actualWidth - constants.GAME_WIDTH * scale) / 2
    local offsetY = (actualHeight - constants.GAME_HEIGHT * scale) / 2
    
    -- 背景色
    love.graphics.clear(constants.MORANDI_COLORS.background)
    
    -- 套用變換 (置中)
    love.graphics.push()
    love.graphics.translate(offsetX, offsetY)
    
    -- 保存狀態並進行世界座標縮放 (用於遊戲物件)
    love.graphics.push()
    love.graphics.scale(scale, scale)
    StateManager.draw()
    love.graphics.pop()
    
    -- 繪製介面 (在縮放之外以原生解析度呈現，確保文字清晰)
    StateManager.drawUI(scale)
    
    love.graphics.pop()
end

function love.keypressed(key, scancode)
    -- 全域全螢幕切換
    if scancode == 'f' then
        love.window.setFullscreen(not love.window.getFullscreen(), "desktop")
        return
    end
    
    StateManager.keypressed(key, scancode)
end

function love.keyreleased(key, scancode)
    StateManager.keyreleased(key, scancode)
end

function love.resize(w, h)
    -- 更新字體縮放
    local scale = math.min(w / constants.GAME_WIDTH, h / constants.GAME_HEIGHT)
    ResourceManager.updateFont(scale)
end