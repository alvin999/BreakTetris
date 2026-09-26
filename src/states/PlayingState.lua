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
        LASER = 0
    }
    self.hasSafetyFloor = false
    self.explosions = {} -- 3x3 蓄力爆破特效陣列
    
    -- 洛克人蓄力集氣系統 (按住空白鍵)
    self.chargeTime = 0
    self.isCharging = false
    self.chargeSoundPlayed = false
    self.chargeReleaseTimer = 0
    
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
    self.explosions = {}
    self.chargeTime = 0
    self.isCharging = false
    self.chargeSoundPlayed = false
    self.chargeReleaseTimer = 0
    self.paddle.chargeRatio = 0
    self.paddle:shrinkToBase()
    self.paddle.hasLaser = false
    for _, b in ipairs(self.balls) do
        b.isPenetrating = false
        b.isChargedBomb = false
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
        local pool = {"LONG", "MULTI", "PIERCE", "SAFETY", "LASER"}
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
    elseif typeKey == "LASER" then
        self.activeEffects.LASER = info.duration
        self.paddle.hasLaser = true
    end
end

-- 發射雷射光束 (裝備雷射道具時)
function PlayingState:fireLaser()
    if self.activeEffects.LASER > 0 and self.laserCooldown <= 0 then
        self.laserCooldown = 0.20
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
    
    -- 洛克人模式：按住空白鍵蓄力 (Hold Space to Charge)
    local maxCharge = constants.MAX_CHARGE_TIME or 0.9
    local isSpaceDown = love.keyboard.isDown("space")
    if isSpaceDown then
        self.isCharging = true
        self.chargeTime = self.chargeTime + dt
        self.chargeReleaseTimer = 0
        if self.chargeTime >= maxCharge then
            if not self.chargeSoundPlayed then
                ResourceManager.playSound("start") -- 滿氣提示聲改為開始遊戲的叮咚聲 (start)
                self.chargeSoundPlayed = true
            end
        end
    else
        if self.isCharging then
            -- 放開空白鍵：若已蓄滿，啟動放開揮拍擊打窗口 (與 slam_window_timer 同步)
            if self.chargeTime >= maxCharge then
                self.chargeReleaseTimer = constants.SLAM_WINDOW_DURATION or 0.25
            end
            self.isCharging = false
            self.chargeTime = 0
            self.chargeSoundPlayed = false
        end
        
        -- 更新放開後板子蓄力保持倒數
        if self.chargeReleaseTimer > 0 then
            self.chargeReleaseTimer = self.chargeReleaseTimer - dt
            if self.chargeReleaseTimer <= 0 then
                self.chargeReleaseTimer = 0
            end
        end
    end
    
    -- 同步板子跑馬燈進度 (蓄力中或蓄滿揮拍窗口中維持發光)
    local displayRatio = 0
    if self.isCharging then
        displayRatio = self.chargeTime / maxCharge
    elseif self.chargeReleaseTimer > 0 then
        displayRatio = 1.0
    end
    self.paddle.chargeRatio = displayRatio
    
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
            -- 雷射不掉落道具，防止滾雪球
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
            -- 只有在放開瞬間揮拍擊中球時，才將板子上的蓄力能量貫注到球中！按住接球不加速也不引爆
            if self.chargeReleaseTimer > 0 then
                ball.isChargedBomb = true
                ResourceManager.playSound("lock") -- 蓄力殺球擊發破空音效！
                self.chargeTime = 0
                self.chargeReleaseTimer = 0
                self.chargeSoundPlayed = false
                self.paddle.chargeRatio = 0
            end
        elseif res.event == "CHARGED_EXPLODE" then
            ResourceManager.playSound("clear") -- 3x3 引爆清爽消除音效！
            -- 3x3 九宮格磚塊範圍爆破
            local destroyedCount = 0
            for r = math.max(1, res.row - 1), math.min(self.grid.height, res.row + 1) do
                for c = math.max(1, res.col - 1), math.min(self.grid.width, res.col + 1) do
                    if self.grid.data[r][c] ~= 0 then
                        self.grid.data[r][c] = 0
                        destroyedCount = destroyedCount + 1
                    end
                end
            end
            self.score = self.score + destroyedCount * 50
            -- 產生 3x3 莫蘭迪暖杏橘爆破擴散光環
            table.insert(self.explosions, {
                x = res.x,
                y = res.y,
                radius = 12,
                maxRadius = constants.TILE_SIZE * 2.5,
                timer = 0,
                duration = 0.35,
                color = {240/255, 175/255, 115/255}
            })
            self:trySpawnPowerUp(res.x, res.y)
        elseif res.event == "BRICK_HIT" then
            ResourceManager.playSound("blip")
            self.score = self.score + 50
            self:trySpawnPowerUp(res.x, res.y)
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
    
    -- 5. 更新爆破動畫特效
    for i = #self.explosions, 1, -1 do
        local exp = self.explosions[i]
        exp.timer = exp.timer + dt
        if exp.timer >= exp.duration then
            table.remove(self.explosions, i)
        end
    end
    
    -- 6. 檢查磚塊是否全清，若是則回切 Tetris
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
    
    -- 若場上完全沒有方塊，無法切換至打磚塊模式 (必須先在俄羅斯方塊中落下方塊)
    if maxY == 0 then
        ResourceManager.playSound("blip")
        return
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
        
        -- 繪製 3x3 蓄力引爆衝擊圈
        for _, exp in ipairs(self.explosions) do
            local progress = exp.timer / exp.duration
            local radius = exp.radius + (exp.maxRadius - exp.radius) * progress
            local alpha = (1 - progress) * 0.85
            love.graphics.setColor(exp.color[1], exp.color[2], exp.color[3], alpha)
            love.graphics.setLineWidth(3 * (1 - progress * 0.5))
            love.graphics.circle("line", exp.x, exp.y + gridOffsetY, radius)
            love.graphics.setColor(exp.color[1], exp.color[2], exp.color[3], alpha * 0.25)
            love.graphics.circle("fill", exp.x, exp.y + gridOffsetY, radius * 0.7)
        end
        love.graphics.setLineWidth(1)
        
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
        y = y + lineHeight * 1.3
        
        -- 洛克人蓄力 HUD (單行固定排版，避免按鍵時上下推擠換行產生閃爍)
        local contentW = (constants.INFO_WIDTH - 20) * scale
        local barW = 46 * scale
        local barH = 6 * scale
        local barX = uiX + contentW - barW
        local barY = y + math.floor((lineHeight - barH) / 2)
        local maxCharge = constants.MAX_CHARGE_TIME or 0.9
        local cRatio = math.min(1, self.chargeTime / maxCharge)
        
        -- 檢查場上是否有發光蓄力爆破球
        local hasChargedBall = false
        for _, b in ipairs(self.balls) do
            if b.isChargedBomb then
                hasChargedBall = true
                break
            end
        end
        
        local isChargedPaddle = (self.isCharging and cRatio >= 1.0) or (self.chargeReleaseTimer > 0)
        
        if isChargedPaddle then
            local flash = 0.7 + 0.3 * math.sin(love.timer.getTime() * 12)
            love.graphics.setColor(100/255, 220/255, 255/255, flash)
            love.graphics.print("READY!", uiX, y)
            
            love.graphics.setColor(0.2, 0.25, 0.3, 1)
            love.graphics.rectangle("fill", barX, barY, barW, barH, 2, 2)
            love.graphics.setColor(100/255, 220/255, 255/255, flash)
            love.graphics.rectangle("fill", barX, barY, barW, barH, 2, 2)
        elseif self.isCharging then
            love.graphics.setColor(136/255, 186/255, 218/255, 1)
            love.graphics.print(string.format("CHG %d%%", math.floor(cRatio * 100)), uiX, y)
            
            love.graphics.setColor(0.2, 0.25, 0.3, 1)
            love.graphics.rectangle("fill", barX, barY, barW, barH, 2, 2)
            love.graphics.setColor(136/255, 186/255, 218/255, 0.9)
            love.graphics.rectangle("fill", barX, barY, barW * cRatio, barH, 2, 2)
        elseif hasChargedBall then
            love.graphics.setColor(245/255, 185/255, 125/255, 1)
            love.graphics.print("3x3 BOMB", uiX, y)
            
            love.graphics.setColor(0.2, 0.25, 0.3, 1)
            love.graphics.rectangle("fill", barX, barY, barW, barH, 2, 2)
            love.graphics.setColor(245/255, 185/255, 125/255, 0.9)
            love.graphics.rectangle("fill", barX, barY, barW, barH, 2, 2)
        else
            love.graphics.setColor(0.65, 0.65, 0.65, 1)
            love.graphics.print("CHARGE", uiX, y)
            
            love.graphics.setColor(0.2, 0.22, 0.25, 1)
            love.graphics.rectangle("fill", barX, barY, barW, barH, 2, 2)
            love.graphics.setColor(0.4, 0.45, 0.5, 0.5)
            love.graphics.rectangle("line", barX, barY, barW, barH, 2, 2)
        end
        
        -- 單行固定高度，無論何時 Y 座標永遠固定
        y = y + lineHeight * 1.2
        
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
        
        -- 持續性道具倒數顯示 (移除 COLOR_BOMB)
        local effectList = {"LONG", "PIERCE", "LASER"}
        local itemBarW = 100 * scale
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
                local maxDuration = (effKey == "LONG" and 30) or info.duration
                local pct = math.min(1, remTime / maxDuration)
                love.graphics.setColor(0.3, 0.3, 0.3, 1)
                love.graphics.rectangle("fill", uiX, y, itemBarW, 3 * scale)
                love.graphics.setColor(info.color)
                love.graphics.rectangle("fill", uiX, y, itemBarW * pct, 3 * scale)
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
            love.graphics.print("Fire Gun: SPACE", uiX, y)
            love.graphics.setColor(1, 1, 1, 1)
            y = y + lineHeight
        end
        love.graphics.print("Charge: Hold SPACE", uiX, y)
        y = y + lineHeight
        love.graphics.print("Release: 3x3 Blast", uiX, y)
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
