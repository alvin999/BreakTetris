-- src/states/PlayingState.lua
local BaseState = require("src.states.BaseState")
local StateManager = require("src.states.StateManager")
local ResourceManager = require("src.managers.ResourceManager")
local constants = require("src.constants")
local Grid = require("src.components.Grid")
local Piece = require("src.components.Piece")
local Paddle = require("src.components.Paddle")
local Ball = require("src.components.Ball")
local PowerUp = require("src.components.PowerUp")
local Laser = require("src.components.Laser")

local PlayingState = setmetatable({}, BaseState)
PlayingState.__index = PlayingState

function PlayingState.new()
    local self = setmetatable({}, PlayingState)
    self.grid = Grid.new()
    self.paddle = Paddle.new()
    self.balls = { Ball.new() }
    self.ball = self.balls[1]
    
    -- 道具與雷射系統
    self.powerUps = {}
    self.lasers = {}
    self.laserCooldown = 0
    self.activeEffects = {
        LONG = 0,
        PIERCE = 0,
        COLOR_BOMB = 0,
        LASER = 0
    }
    self.hasSafetyFloor = false
    
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
    self.balls = { Ball.new() }
    self.ball = self.balls[1]
    self:clearBreakoutItems()
    
    self.score = 0
    self.level = 1
    self.lines = 0
    self.mode = "TETRIS"
    self.isAnimating = false
    self:spawnNewPiece()
end

function PlayingState:clearBreakoutItems()
    self.powerUps = {}
    self.lasers = {}
    self.laserCooldown = 0
    for k in pairs(self.activeEffects) do
        self.activeEffects[k] = 0
    end
    self.hasSafetyFloor = false
    self.paddle:shrinkToBase()
    self.paddle.hasLaser = false
    for _, b in ipairs(self.balls) do
        b.isPenetrating = false
    end
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

    -- 下落邏輯
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

-- ===================================
-- 道具系統核心方法
-- ===================================

function PlayingState:trySpawnPowerUp(x, y)
    if math.random() <= constants.POWERUP_DROP_CHANCE then
        local pool = {"LONG", "MULTI", "PIERCE", "SAFETY", "COLOR_BOMB", "LASER"}
        local selected = pool[math.random(#pool)]
        table.insert(self.powerUps, PowerUp.new(x, y, selected))
    end
end

function PlayingState:applyPowerUp(typeKey)
    ResourceManager.playSound("start")
    local info = constants.POWERUP_TYPES[typeKey]
    if not info then return end

    if typeKey == "LONG" then
        -- 每次拾取累加時效 (最長 30 秒) 並累積加長板子
        self.activeEffects.LONG = math.min(30, math.max(self.activeEffects.LONG + 10, info.duration))
        self.paddle:expand()
    elseif typeKey == "MULTI" then
        -- 複製當前場上的球，發射偏轉角度
        local atan2 = math.atan2 or math.atan
        local newBalls = {}
        for _, b in ipairs(self.balls) do
            if #self.balls + #newBalls < 16 then
                local speed = math.sqrt(b.dx * b.dx + b.dy * b.dy)
                local currentAngle = atan2(b.dy, b.dx)
                local angle1 = currentAngle + math.rad(30)
                local angle2 = currentAngle - math.rad(30)
                
                local b1 = Ball.new(b.x, b.y, speed * math.cos(angle1), speed * math.sin(angle1))
                local b2 = Ball.new(b.x, b.y, speed * math.cos(angle2), speed * math.sin(angle2))
                b1.isPenetrating = b.isPenetrating
                b2.isPenetrating = b.isPenetrating
                table.insert(newBalls, b1)
                table.insert(newBalls, b2)
            end
        end
        for _, nb in ipairs(newBalls) do
            table.insert(self.balls, nb)
        end
    elseif typeKey == "PIERCE" then
        self.activeEffects.PIERCE = info.duration
    elseif typeKey == "SAFETY" then
        self.hasSafetyFloor = true
    elseif typeKey == "COLOR_BOMB" then
        self.activeEffects.COLOR_BOMB = info.duration
    elseif typeKey == "LASER" then
        self.activeEffects.LASER = info.duration
        self.paddle.hasLaser = true
    end
end

-- 同色連鎖爆破邏輯 (BFS 擴散)
function PlayingState:triggerColorBomb(startRow, startCol, targetType)
    if not targetType or targetType == 0 then return end
    
    local queue = { {r = startRow, c = startCol} }
    local directions = { {1,0}, {-1,0}, {0,1}, {0,-1} }
    
    while #queue > 0 do
        local curr = table.remove(queue, 1)
        for _, dir in ipairs(directions) do
            local nr = curr.r + dir[1]
            local nc = curr.c + dir[2]
            if nr >= 1 and nr <= self.grid.height and nc >= 1 and nc <= self.grid.width then
                if self.grid.data[nr][nc] == targetType then
                    self.grid.data[nr][nc] = 0
                    self.score = self.score + 50
                    table.insert(queue, {r = nr, c = nc})
                    -- 連鎖引爆小機率產生掉落物
                    if math.random() < 0.2 then
                        self:trySpawnPowerUp((nc - 0.5) * constants.TILE_SIZE, (nr - 0.5) * constants.TILE_SIZE)
                    end
                end
            end
        end
    end
end

-- 發射雷射光束
function PlayingState:fireLaser()
    if self.activeEffects.LASER > 0 and self.laserCooldown <= 0 then
        self.laserCooldown = 0.25
        ResourceManager.playSound("blip")
        local leftGunX = self.paddle.x + 5
        local rightGunX = self.paddle.x + self.paddle.w - 5
        local gunY = self.paddle.y - 4
        table.insert(self.lasers, Laser.new(leftGunX, gunY))
        table.insert(self.lasers, Laser.new(rightGunX, gunY))
    end
end

function PlayingState:updateBreakout(dt)
    self.paddle:update(dt)
    
    -- 雷射發射冷卻
    if self.laserCooldown > 0 then
        self.laserCooldown = self.laserCooldown - dt
    end
    
    -- 1. 更新持續性道具 Buff
    for effectKey, timer in pairs(self.activeEffects) do
        if timer > 0 then
            self.activeEffects[effectKey] = timer - dt
            if self.activeEffects[effectKey] <= 0 then
                self.activeEffects[effectKey] = 0
                -- 效果結束回調
                if effectKey == "LONG" then
                    self.paddle:shrinkToBase()
                elseif effectKey == "LASER" then
                    self.paddle.hasLaser = false
                end
            end
        end
    end
    
    local isPierce = (self.activeEffects.PIERCE > 0)
    
    -- 2. 更新雷射光束
    for i = #self.lasers, 1, -1 do
        local laser = self.lasers[i]
        local hit = laser:update(dt, self.grid)
        if hit == "OUT" then
            table.remove(self.lasers, i)
        elseif type(hit) == "table" and hit.hit then
            table.remove(self.lasers, i)
            self.score = self.score + 50
            ResourceManager.playSound("blip")
            self:trySpawnPowerUp(hit.x, hit.y)
            if self.activeEffects.COLOR_BOMB > 0 then
                self:triggerColorBomb(hit.row, hit.col, hit.tileType)
            end
        end
    end
    
    -- 3. 更新掉落道具膠囊
    for i = #self.powerUps, 1, -1 do
        local p = self.powerUps[i]
        p:update(dt)
        if p:checkCollision(self.paddle) then
            self:applyPowerUp(p.typeKey)
            self.score = self.score + 100
            table.remove(self.powerUps, i)
        elseif p:isOutOfBounds() then
            table.remove(self.powerUps, i)
        end
    end
    
    -- 4. 更新球體群
    for i = #self.balls, 1, -1 do
        local ball = self.balls[i]
        ball.isPenetrating = isPierce
        
        local res = ball:update(dt, self.paddle, self.grid, self.hasSafetyFloor)
        
        if res.event == "SAFETY_HIT" then
            self.hasSafetyFloor = false
            ResourceManager.playSound("lock")
        elseif res.event == "PADDLE_HIT" then
            ResourceManager.playSound("blip")
        elseif res.event == "BRICK_HIT" then
            ResourceManager.playSound("blip")
            self.score = self.score + 50
            self:trySpawnPowerUp(res.x, res.y)
            if self.activeEffects.COLOR_BOMB > 0 then
                self:triggerColorBomb(res.row, res.col, res.tileType)
            end
        elseif res.event == "DROP" then
            table.remove(self.balls, i)
            if #self.balls == 0 then
                ResourceManager.playSound("endgame")
                StateManager.switch("gameover", {score = self.score})
                return
            end
        end
    end
    
    -- 同步引用保持相容
    self.ball = self.balls[1]
    
    -- 5. 檢查磚塊是否全清，若是則回切 Tetris
    local remaining = 0
    for r = 1, self.grid.height do
        for c = 1, self.grid.width do
            if self.grid.data[r][c] ~= 0 then remaining = remaining + 1 end
        end
    end
    if remaining == 0 and not self.isAnimating then
        self:switchToTetris()
    end
end

function PlayingState:switchToBreakout()
    if self.isAnimating then return end
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
    
    -- 若俄羅斯方塊場上無方塊，自動生成 2 排隨機莫蘭迪方塊供玩家遊玩打磚塊
    if maxY == 0 then
        local types = {"I", "O", "T", "L", "J", "S", "Z"}
        for r = 1, 2 do
            for c = 1, self.grid.width do
                self.grid.data[r][c] = types[math.random(#types)]
            end
        end
        minY = 1
        maxY = 2
    end
    
    local rowsToKeep = {}
    for r = minY, maxY do
        table.insert(rowsToKeep, self.grid.data[r])
    end
    
    self.isAnimating = true
    self.animationTimer = 0
    self.startGridY = 0
    self.targetGridY = -(minY - 1) * constants.TILE_SIZE
    self._nextMode = "BREAKOUT"
    self._rowsToKeep = rowsToKeep
end

function PlayingState:switchToTetris()
    if self.isAnimating then return end
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
    
    -- 當方塊已經被清光時，直接無縫切回 TETRIS 模式
    if maxY == 0 then
        self.mode = "TETRIS"
        self:clearBreakoutItems()
        self.grid:reset()
        self:spawnNewPiece()
        ResourceManager.playSound("start")
        return
    end
    
    local rowsToKeep = {}
    for r = minY, maxY do
        table.insert(rowsToKeep, self.grid.data[r])
    end
    
    self.isAnimating = true
    self.animationTimer = 0
    self.startGridY = 0
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
        self.balls = { Ball.new() }
        self.ball = self.balls[1]
        self.paddle:reset()
        self:clearBreakoutItems()
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
        self:clearBreakoutItems()
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
    
    -- 繪製網格
    self.grid:draw(gridOffsetY)
    
    if self.mode == "TETRIS" and self.currentPiece then
        self.currentPiece:draw(gridOffsetY, self.showGhostPiece, self.grid)
    elseif self.mode == "BREAKOUT" then
        -- 繪製安全護網 (若啟動中)
        if self.hasSafetyFloor then
            love.graphics.setColor(constants.POWERUP_TYPES.SAFETY.color)
            love.graphics.setLineWidth(2)
            local bottomY = (constants.GRID_HEIGHT * constants.TILE_SIZE) - 2 + gridOffsetY
            love.graphics.line(0, bottomY, constants.GRID_WIDTH * constants.TILE_SIZE, bottomY)
            love.graphics.setLineWidth(1)
        end
        
        -- 繪製雷射光束
        for _, l in ipairs(self.lasers) do
            l:draw(gridOffsetY)
        end
        
        -- 繪製板子與多顆球
        self.paddle:draw(gridOffsetY)
        for _, b in ipairs(self.balls) do
            b:draw(gridOffsetY)
        end
        
        -- 繪製下落中的道具膠囊
        for _, p in ipairs(self.powerUps) do
            p:draw(gridOffsetY)
        end
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
    
    if self.mode == "TETRIS" then
        -- Next Piece Preview
        if self.nextPieceType then
            love.graphics.print("NEXT PIECE:", uiX, y)
            
            local nextShape = constants.PIECES[self.nextPieceType][1]
            local nextColor = constants.MORANDI_COLORS[self.nextPieceType]
            
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
        
        love.graphics.print("LEVEL: " .. self.level, uiX, y)
        y = y + lineHeight
        love.graphics.print("LINES: " .. self.lines, uiX, y)
        y = y + lineHeight * 1.5
    else
        -- 打磚塊模式專屬資訊區
        love.graphics.print("BALLS: " .. #self.balls, uiX, y)
        y = y + lineHeight * 1.5
        
        love.graphics.setColor(0.9, 0.9, 0.9, 1)
        love.graphics.print("ACTIVE ITEMS:", uiX, y)
        y = y + lineHeight
        
        local hasActiveItem = false
        
        -- 安全護網顯示
        if self.hasSafetyFloor then
            hasActiveItem = true
            love.graphics.setColor(constants.POWERUP_TYPES.SAFETY.color)
            love.graphics.print("[S] Safety: READY", uiX, y)
            y = y + lineHeight
        end
        
        -- 持續性道具倒數顯示
        local effectList = {"LONG", "PIERCE", "COLOR_BOMB", "LASER"}
        for _, effKey in ipairs(effectList) do
            local remTime = self.activeEffects[effKey]
            if remTime > 0 then
                hasActiveItem = true
                local info = constants.POWERUP_TYPES[effKey]
                love.graphics.setColor(info.color)
                local timeStr = string.format("%.1fs", remTime)
                
                -- 若為加長道具，以 x1, x2, x3 為單位顯示累積加長倍數
                if effKey == "LONG" then
                    local maxW = constants.PADDLE_MAX_WIDTH or 200
                    local level = math.max(1, self.paddle.expandLevel or 1)
                    if self.paddle.target_w >= maxW then
                        love.graphics.print(string.format("[%s] %s x%d (MAX): %s", info.code, info.name, level, timeStr), uiX, y)
                    else
                        love.graphics.print(string.format("[%s] %s x%d: %s", info.code, info.name, level, timeStr), uiX, y)
                    end
                else
                    love.graphics.print(string.format("[%s] %s: %s", info.code, info.name, timeStr), uiX, y)
                end
                y = y + lineHeight * 0.9
                
                -- 進度條
                local barW = 100 * scale
                local barH = 3 * scale
                local maxDuration = (effKey == "LONG" and 30) or info.duration
                local pct = math.min(1, remTime / maxDuration)
                love.graphics.setColor(0.3, 0.3, 0.3, 1)
                love.graphics.rectangle("fill", uiX, y, barW, barH)
                love.graphics.setColor(info.color)
                love.graphics.rectangle("fill", uiX, y, barW * pct, barH)
                y = y + lineHeight * 0.6
            end
        end
        
        if not hasActiveItem then
            love.graphics.setColor(0.6, 0.6, 0.6, 1)
            love.graphics.print("(Break bricks to get)", uiX, y)
            y = y + lineHeight
        end
        
        love.graphics.setColor(1, 1, 1, 1)
        y = y + lineHeight
    end
    
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
        love.graphics.print("Move: H/L, A/D, <-/->", uiX, y)
        y = y + lineHeight
        if self.activeEffects.LASER > 0 then
            love.graphics.setColor(constants.POWERUP_TYPES.LASER.color)
            love.graphics.print("Fire & Slam: SPACE", uiX, y)
            love.graphics.setColor(1, 1, 1, 1)
        else
            love.graphics.print("Slam: SPACE", uiX, y)
        end
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
        if self.activeEffects.LASER > 0 then
            self:fireLaser()
        end
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
