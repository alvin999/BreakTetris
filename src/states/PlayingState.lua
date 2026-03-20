-- src/states/PlayingState.lua
local BaseState = require("src.states.BaseState")
local StateManager = require("src.states.StateManager")
local ResourceManager = require("src.managers.ResourceManager")
local constants = require("src.constants")
local Grid = require("src.components.Grid")
local Piece = require("src.components.Piece")
local Paddle = require("src.components.Paddle")
local Ball = require("src.components.Ball")

local PlayingState = setmetatable({}, BaseState)
PlayingState.__index = PlayingState

function PlayingState.new()
    local self = setmetatable({}, PlayingState)
    self.grid = Grid.new()
    self.paddle = Paddle.new()
    self.ball = Ball.new()
    self.currentPiece = nil
    self.nextPieceType = nil
    self.score = 0
    self.level = 1
    self.lines = 0
    self.mode = "TETRIS"
    self.showGhostPiece = true
    
    -- 動畫與狀態
    self.isAnimating = false
    self.animationTimer = 0
    self.gridOffsetY = 0
    self.currentGridY = 0
    
    -- 移動與下落控制
    self.pieceTimer = 0
    self.lockTimer = 0
    self.moveDirection = 0
    self.moveTimer = 0
    self.isSoftDropping = false
    
    return self
end

function PlayingState:enter(params)
    if params and params.reset then
        self:reset()
    end
end

function PlayingState:reset()
    self.grid:reset()
    self.paddle:reset()
    self.ball:reset()
    self.score = 0
    self.level = 1
    self.lines = 0
    self.mode = "TETRIS"
    self.isAnimating = false
    self:spawnNewPiece()
end

function PlayingState:spawnNewPiece()
    local types = {"I", "O", "T", "L", "J", "S", "Z"}
    local pieceType = self.nextPieceType or types[math.random(#types)]
    self.currentPiece = Piece.new(pieceType)
    self.nextPieceType = types[math.random(#types)]
end

function PlayingState:update(dt)
    if self.isAnimating then
        self:updateAnimation(dt)
        return
    end

    if self.mode == "TETRIS" then
        self:updateTetris(dt)
    else
        self:updateBreakout(dt)
    end
end

function PlayingState:updateAnimation(dt)
    self.animationTimer = self.animationTimer + dt
    local t = math.min(self.animationTimer / constants.ANIMATION_DURATION, 1)
    
    -- 線性插值計算 Y 偏移
    self.currentGridY = self.startGridY + (self.targetGridY - self.startGridY) * t
    
    if t >= 1 then
        self:finishAnimation()
    end
end

function PlayingState:updateTetris(dt)
    -- 本地存取以簡化程式碼
    local piece = self.currentPiece
    if not piece then return end

    -- 處理水平持續移動 (ARR/DAS)
    if self.moveDirection ~= 0 then
        self.moveTimer = self.moveTimer + dt
        if self.moveTimer >= 0 then
            if piece:move(self.moveDirection, 0, self.grid) then
                self.lockTimer = 0
            end
            self.moveTimer = constants.MOVE_INTERVAL
        end
    end

    -- 下落邏輯 (修正：使用 utils.checkCollision 進行不帶位移的檢查)
    local utils = require("src.utils")
    local isOnGround = utils.checkCollision(piece.x, piece.y + 1, piece.shape, self.grid.data, self.grid.width, self.grid.height)
    
    if isOnGround then
        self.lockTimer = self.lockTimer + dt
        if self.lockTimer >= constants.LOCK_DELAY then
            self:lockPiece()
        end
    else
        self.lockTimer = 0
        local baseDropInterval = math.max(0.1, 1.0 - (self.level - 1) * 0.05)
        local dropInterval = self.isSoftDropping and 0.05 or baseDropInterval
        
        self.pieceTimer = self.pieceTimer + dt
        if self.pieceTimer >= dropInterval then
            self.pieceTimer = 0
            piece:move(0, 1, self.grid)
        end
    end
end

function PlayingState:lockPiece()
    ResourceManager.playSound("lock")
    local gameOver = self.grid:lockPiece(self.currentPiece)
    
    if gameOver then
        StateManager.switch("gameover", {score = self.score})
        return
    end
    
    -- 重置移動狀態
    self.isSoftDropping = false
    self.moveDirection = 0
    self.moveTimer = 0
    self.lockTimer = 0
    
    -- 檢查消行
    local lines = self.grid:checkLines()
    if lines > 0 then
        ResourceManager.playSound("clear")
        self.score = self.score + lines * 100
        self.lines = self.lines + lines
        self.level = math.min(math.floor(self.lines / 10) + 1, 100)
    end
    
    self:spawnNewPiece()
end

function PlayingState:updateBreakout(dt)
    self.paddle:update(dt)
    local event = self.ball:update(dt, self.paddle, self.grid)
    
    if event == "PADDLE_HIT" or event == "BRICK_HIT" then
        ResourceManager.playSound("blip")
        
        -- 檢查是否全清，若是則回切 Tetris
        local remaining = 0
        for r = 1, self.grid.height do
            for c = 1, self.grid.width do
                if self.grid.data[r][c] ~= 0 then remaining = remaining + 1 end
            end
        end
        if remaining == 0 then
            self:switchToTetris()
        end
        
        if event == "BRICK_HIT" then
            self.score = self.score + 50
        end
    elseif event == "DROP" then
        ResourceManager.playSound("endgame")
        StateManager.switch("gameover", {score = self.score})
    end
end

function PlayingState:switchToBreakout()
    print("Transition: Tetris -> Breakout")
    local minY, maxY = self.grid.height + 1, 0
    for r = 1, self.grid.height do
        local hasTile = false
        for c = 1, self.grid.width do
            if self.grid.data[r][c] ~= 0 then hasTile = true; break end
        end
        if hasTile then
            minY = math.min(minY, r)
            maxY = math.max(maxY, r)
        end
    end
    
    if maxY == 0 then return end -- 沒東西就不轉移
    
    local rowsToKeep = {}
    for r = minY, maxY do
        table.insert(rowsToKeep, self.grid.data[r])
    end
    
    self.isAnimating = true
    self.animationTimer = 0
    self.startGridY = 0
    -- 將第一行方塊 (minY) 移動到螢幕頂部 (1)
    self.targetGridY = -(minY - 1) * constants.TILE_SIZE
    self._nextMode = "BREAKOUT"
    self._rowsToKeep = rowsToKeep
end

function PlayingState:switchToTetris()
    print("Transition: Breakout -> Tetris")
    local minY, maxY = self.grid.height + 1, 0
    for r = 1, self.grid.height do
        local hasTile = false
        for c = 1, self.grid.width do
            if self.grid.data[r][c] ~= 0 then hasTile = true; break end
        end
        if hasTile then
            minY = math.min(minY, r)
            maxY = math.max(maxY, r)
        end
    end
    
    if maxY == 0 then return end
    
    local rowsToKeep = {}
    for r = minY, maxY do
        table.insert(rowsToKeep, self.grid.data[r])
    end
    
    self.isAnimating = true
    self.animationTimer = 0
    self.startGridY = 0
    -- 將最後一行方塊 (maxY) 移動到螢幕底部 (GridHeight)
    self.targetGridY = (self.grid.height - maxY) * constants.TILE_SIZE
    self._nextMode = "TETRIS"
    self._rowsToKeep = rowsToKeep
end

function PlayingState:finishAnimation()
    self.isAnimating = false
    self.currentGridY = 0
    ResourceManager.playSound("start")
    
    local newGridData = {}
    local numRows = #self._rowsToKeep
    
    if self._nextMode == "BREAKOUT" then
        self.mode = "BREAKOUT"
        self.ball:reset()
        self.paddle:reset()
        -- 磚塊靠頂部
        for r = 1, self.grid.height do
            if r <= numRows then
                newGridData[r] = self._rowsToKeep[r]
            else
                newGridData[r] = {}
                for c = 1, self.grid.width do newGridData[r][c] = 0 end
            end
        end
    else
        self.mode = "TETRIS"
        self:spawnNewPiece()
        -- 磚塊靠底部
        for r = 1, self.grid.height do
            if r <= self.grid.height - numRows then
                newGridData[r] = {}
                for c = 1, self.grid.width do newGridData[r][c] = 0 end
            else
                newGridData[r] = self._rowsToKeep[r - (self.grid.height - numRows)]
            end
        end
    end
    self.grid.data = newGridData
end

function PlayingState:draw()
    local gridOffsetY = self.isAnimating and self.currentGridY or 0
    
    -- 繪製元件 (世界座標)
    self.grid:draw(gridOffsetY)
    
    if self.mode == "TETRIS" and self.currentPiece then
        self.currentPiece:draw(gridOffsetY, self.showGhostPiece, self.grid)
    elseif self.mode == "BREAKOUT" then
        self.paddle:draw(gridOffsetY)
        self.ball:draw(gridOffsetY)
    end
end

function PlayingState:drawUI(scale)
    scale = scale or 1
    love.graphics.setFont(ResourceManager.font)
    love.graphics.setColor(1, 1, 1, 1)
    
    local margin = 10 * scale
    local uiX = (constants.GRID_WIDTH * constants.TILE_SIZE) * scale + margin
    local y = margin
    local lineHeight = ResourceManager.font:getHeight() * 1.2
    
    love.graphics.print("MODE: " .. self.mode, uiX, y)
    y = y + lineHeight
    love.graphics.print("(C to switch)", uiX, y)
    y = y + lineHeight * 1.5
    
    love.graphics.print("SCORE: " .. self.score, uiX, y)
    y = y + lineHeight * 1.5
    
    -- Next Piece Preview (比照備份檔優化佈局)
    if self.mode == "TETRIS" and self.nextPieceType then
        love.graphics.print("NEXT PIECE:", uiX, y)
        
        local nextShape = constants.PIECES[self.nextPieceType][1]
        local nextColor = constants.MORANDI_COLORS[self.nextPieceType]
        
        -- 計算方塊實際高度以進行居中
        local minY, maxY = #nextShape + 1, 0
        for r = 1, #nextShape do
            for c = 1, #nextShape[r] do
                if nextShape[r][c] == 1 then
                    minY = math.min(minY, r)
                    maxY = math.max(maxY, r)
                end
            end
        end
        local piecePixelHeight = (maxY - minY + 1) * constants.TILE_SIZE
        local previewBoxHeight = 2 * constants.TILE_SIZE
        local verticalOffset = (previewBoxHeight - piecePixelHeight) / 2

        local drawStartX = uiX + (5 * scale)
        local drawStartY = y + lineHeight
        
        love.graphics.setColor(nextColor)
        for r = 1, #nextShape do
            for c = 1, #nextShape[r] do
                if nextShape[r][c] == 1 then
                    local rx = drawStartX + (c - 1) * constants.TILE_SIZE * scale
                    local ry = drawStartY + (r - minY) * constants.TILE_SIZE * scale + (verticalOffset * scale)
                    love.graphics.rectangle("fill", rx, ry, constants.TILE_SIZE * scale, constants.TILE_SIZE * scale)
                    
                    love.graphics.setColor(constants.MORANDI_COLORS.background)
                    love.graphics.rectangle("line", rx, ry, constants.TILE_SIZE * scale, constants.TILE_SIZE * scale)
                    love.graphics.setColor(nextColor)
                end
            end
        end
        love.graphics.setColor(1, 1, 1, 1)
        y = y + lineHeight + (previewBoxHeight + 10) * scale
    end
    
    -- 等級和行數
    love.graphics.print("LEVEL: " .. self.level, uiX, y)
    y = y + lineHeight
    love.graphics.print("LINES: " .. self.lines, uiX, y)
    y = y + lineHeight * 1.5
    
    -- 控制說明
    love.graphics.print("CONTROLS:", uiX, y)
    y = y + lineHeight
    love.graphics.print("Fullscreen: F", uiX, y)
    y = y + lineHeight
    love.graphics.print("Pause: P", uiX, y)
    y = y + lineHeight
    love.graphics.print("Mute (M): " .. (ResourceManager.soundEnabled and "Off" or "On"), uiX, y)
    y = y + lineHeight * 1.5
    
    if self.mode == "TETRIS" then
        love.graphics.print("--- TETRIS ---", uiX, y)
        y = y + lineHeight
        love.graphics.print("Move: H/L or <-/->", uiX, y)
        y = y + lineHeight
        love.graphics.print("Rotate: K or UP", uiX, y)
        y = y + lineHeight
        love.graphics.print("Hard Drop: SPACE", uiX, y)
        y = y + lineHeight
        love.graphics.print("Ghost Toggle: G", uiX, y)
    else
        love.graphics.print("--- BREAKOUT ---", uiX, y)
        y = y + lineHeight
        love.graphics.print("Move: H/L or <-/->", uiX, y)
        y = y + lineHeight
        love.graphics.print("Slam: SPACE", uiX, y)
    end
end

function PlayingState:keypressed(key, scancode)
    if scancode == "p" then
        StateManager.switch("paused")
        return
    end

    if scancode == 'c' then
        if self.mode == "TETRIS" then self:switchToBreakout() else self:switchToTetris() end
        return
    end
    
    if scancode == 'm' then
        ResourceManager.soundEnabled = not ResourceManager.soundEnabled
        return
    end

    if self.mode == "TETRIS" then
        self:handleTetrisInput(scancode)
    else
        self:handleBreakoutInput(scancode)
    end
end

function PlayingState:handleTetrisInput(scancode)
    local p = self.currentPiece
    if not p then return end
    
    if scancode == 'left' or scancode == 'h' then
        self.moveDirection = -1
        p:move(-1, 0, self.grid)
        self.moveTimer = -constants.MOVE_DELAY
    elseif scancode == 'right' or scancode == 'l' then
        self.moveDirection = 1
        p:move(1, 0, self.grid)
        self.moveTimer = -constants.MOVE_DELAY
    elseif scancode == 'up' or scancode == 'k' then
        if p:rotate(self.grid) then self.lockTimer = 0 end
    elseif scancode == 'down' or scancode == 'j' then
        self.isSoftDropping = true
    elseif scancode == 'space' then
        local ghostY = p:calculateGhostY(self.grid)
        if ghostY then p.y = ghostY end
        self:lockPiece()
    elseif scancode == 'g' then
        self.showGhostPiece = not self.showGhostPiece
    end
end

function PlayingState:handleBreakoutInput(scancode)
    if scancode == 'left' or scancode == 'a' or scancode == 'h' then
        self.paddle.dy = -self.paddle.speed
    elseif scancode == 'right' or scancode == 'd' or scancode == 'l' then
        self.paddle.dy = self.paddle.speed
    elseif scancode == 'space' then
        self.paddle.is_slamming = true
    end
end

function PlayingState:keyreleased(key, scancode)
    if self.mode == "TETRIS" then
        if scancode == 'down' or scancode == 'j' then self.isSoftDropping = false end
        if (scancode == 'left' or scancode == 'h') and self.moveDirection == -1 then self.moveDirection = 0 end
        if (scancode == 'right' or scancode == 'l') and self.moveDirection == 1 then self.moveDirection = 0 end
    else
        if (scancode == 'left' or scancode == 'a' or scancode == 'h') and self.paddle.dy < 0 then self.paddle.dy = 0 end
        if (scancode == 'right' or scancode == 'd' or scancode == 'l') and self.paddle.dy > 0 then self.paddle.dy = 0 end
        if scancode == 'space' then
            self.paddle.is_slamming = false
            self.paddle.slam_window_timer = constants.SLAM_WINDOW_DURATION
        end
    end
end

return PlayingState
