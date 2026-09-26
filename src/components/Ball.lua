-- src/components/Ball.lua
local constants = require("src.constants")
local utils = require("src.utils")
local Ball = {}
Ball.__index = Ball

function Ball.new(x, y, dx, dy)
    local self = setmetatable({}, Ball)
    self.r = 5
    self.isPenetrating = false
    self.isChargedBomb = false -- 洛克人 3x3 蓄力爆破狀態
    
    if x and y and dx and dy then
        self.x = x
        self.y = y
        self.dx = dx
        self.dy = dy
    else
        self:reset()
    end
    return self
end

function Ball:reset()
    self.x = (constants.GRID_WIDTH * constants.TILE_SIZE) / 2
    self.y = (constants.GRID_HEIGHT * constants.TILE_SIZE) / 2
    self.dx = (math.random() > 0.5 and 1 or -1) * 150
    self.dy = -150
    self.isPenetrating = false
    self.isChargedBomb = false
end

function Ball:update(dt, paddle, grid, hasSafetyFloor)
    local oldX, oldY = self.x, self.y
    local newX = oldX + self.dx * dt
    local newY = oldY + self.dy * dt
    
    local gameAreaWidth = constants.GRID_WIDTH * constants.TILE_SIZE
    local gameAreaHeight = constants.GRID_HEIGHT * constants.TILE_SIZE
    
    -- 1. 牆壁反彈
    if newX - self.r < 0 then
        self.dx = math.abs(self.dx)
        newX = self.r
    elseif newX + self.r > gameAreaWidth then
        self.dx = -math.abs(self.dx)
        newX = gameAreaWidth - self.r
    end
    
    if newY - self.r < 0 then
        self.dy = math.abs(self.dy)
        newY = self.r
    end
    
    -- 出界與安全護網檢查
    if newY + self.r >= gameAreaHeight then
        if hasSafetyFloor then
            self.dy = -math.abs(self.dy)
            self.y = gameAreaHeight - self.r - 2
            return { event = "SAFETY_HIT" }
        else
            return { event = "DROP" }
        end
    end
    
    -- 2. 板子碰撞 (Paddle Collision)
    if self.dy > 0 then
        local collision_y = paddle.original_y
        local y_overlap = (newY + self.r >= collision_y) and (newY - self.r <= collision_y + paddle.h)
        local x_overlap = (newX + self.r >= paddle.x) and (newX - self.r <= paddle.x + paddle.w)
        local coming_from_above = (oldY + self.r <= collision_y + 2)
        
        if y_overlap and x_overlap and coming_from_above then
            self.y = collision_y - self.r
            
            -- 根據擊中板子的位置調整反彈角度 (控球手感增強)
            local paddleCenter = paddle.x + paddle.w / 2
            local hitOffset = (newX - paddleCenter) / (paddle.w / 2) -- -1 到 1
            hitOffset = math.max(-0.9, math.min(0.9, hitOffset))
            
            local currentSpeed = math.sqrt(self.dx * self.dx + self.dy * self.dy)
            -- 只有在放開瞬間 (擊打窗口 slam_window_timer > 0) 才讓球加速，加速幅度溫和調至 1.15 倍 (+15%)
            local isSlammed = (paddle.slam_window_timer > 0)
            if isSlammed then
                currentSpeed = currentSpeed * 1.15
                paddle.slam_window_timer = 0
            end
            
            -- 最大角度調為 52 度 (約 0.9 rad)，防止過度扁平造成垂直推進力失速
            local maxAngle = math.rad(52)
            local bounceAngle = hitOffset * maxAngle
            self.dx = currentSpeed * math.sin(bounceAngle)
            
            -- 垂直向上速度保底機制：保證反彈速度絕對不低於下落垂直速度 (擊打時溫和保底 1.10 倍)
            local minDy = math.abs(self.dy) * (isSlammed and 1.10 or 1.0)
            local calculatedDy = currentSpeed * math.cos(bounceAngle)
            self.dy = -math.max(minDy, calculatedDy)
            
            utils.limitBallSpeed(self, constants.BALL_MAX_SPEED)
            newY = self.y
            return { event = "PADDLE_HIT" }
        end
    end
    
    -- 3. 磚塊碰撞 (Grid Collision)
    local ballTileX = math.floor(newX / constants.TILE_SIZE) + 1
    local ballTileY = math.floor(newY / constants.TILE_SIZE) + 1
    
    local hit_result = nil
    for row = math.max(1, ballTileY - 1), math.min(constants.GRID_HEIGHT, ballTileY + 1) do
        for col = math.max(1, ballTileX - 1), math.min(constants.GRID_WIDTH, ballTileX + 1) do
            if grid.data[row] and grid.data[row][col] ~= 0 then
                local tileX = (col - 1) * constants.TILE_SIZE
                local tileY = (row - 1) * constants.TILE_SIZE
                
                if newX + self.r > tileX and newX - self.r < tileX + constants.TILE_SIZE and
                   newY + self.r > tileY and newY - self.r < tileY + constants.TILE_SIZE then
                   
                    local cellType = grid.data[row][col]
                    
                    -- 若為蓄力爆破球 (3x3 引爆)
                    if self.isChargedBomb then
                        self.isChargedBomb = false
                        
                        -- 物理反彈
                        local centerTileX = tileX + constants.TILE_SIZE / 2
                        local centerTileY = tileY + constants.TILE_SIZE / 2
                        local dx_from_center = newX - centerTileX
                        local dy_from_center = newY - centerTileY
                        
                        if math.abs(dx_from_center) > math.abs(dy_from_center) then
                            self.dx = -self.dx
                            newX = oldX + self.dx * dt
                        else
                            self.dy = -self.dy
                            newY = oldY + self.dy * dt
                        end
                        utils.limitBallSpeed(self, constants.BALL_MAX_SPEED)
                        
                        hit_result = {
                            event = "CHARGED_EXPLODE",
                            row = row,
                            col = col,
                            tileType = cellType,
                            x = tileX + constants.TILE_SIZE / 2,
                            y = tileY + constants.TILE_SIZE / 2
                        }
                        break
                    elseif self.isPenetrating then
                        -- 穿透道具：直接銷毀單格磚塊不反彈
                        grid.data[row][col] = 0
                        hit_result = {
                            event = "BRICK_HIT",
                            row = row,
                            col = col,
                            tileType = cellType,
                            x = tileX + constants.TILE_SIZE / 2,
                            y = tileY + constants.TILE_SIZE / 2
                        }
                        break
                    else
                        -- 一般球：銷毀單格並反彈
                        grid.data[row][col] = 0
                        local centerTileX = tileX + constants.TILE_SIZE / 2
                        local centerTileY = tileY + constants.TILE_SIZE / 2
                        local dx_from_center = newX - centerTileX
                        local dy_from_center = newY - centerTileY
                        
                        if math.abs(dx_from_center) > math.abs(dy_from_center) then
                            self.dx = -self.dx
                            newX = oldX + self.dx * dt
                        else
                            self.dy = -self.dy
                            newY = oldY + self.dy * dt
                        end
                        utils.limitBallSpeed(self, constants.BALL_MAX_SPEED)
                        
                        hit_result = {
                            event = "BRICK_HIT",
                            row = row,
                            col = col,
                            tileType = cellType,
                            x = tileX + constants.TILE_SIZE / 2,
                            y = tileY + constants.TILE_SIZE / 2
                        }
                        break
                    end
                end
            end
        end
        if hit_result then break end
    end
    
    self.x = newX
    self.y = newY
    return hit_result or { event = "NONE" }
end

function Ball:draw(gridOffsetY)
    local oy = gridOffsetY or 0
    local drawY = self.y + oy
    
    -- 洛克人蓄力爆破狀態：球發光 (莫蘭迪琥珀金/暖杏橘高能脈動外環)
    if self.isChargedBomb then
        local t = love.timer.getTime() * 12
        local pulse = 2.5 + math.sin(t) * 1.5
        
        -- 外層發光柔和光暈 (暖橘金)
        love.graphics.setColor(235/255, 178/255, 130/255, 0.5)
        love.graphics.circle("fill", self.x, drawY, self.r + pulse + 2)
        -- 能量光環輪廓
        love.graphics.setColor(255/255, 215/255, 150/255, 0.9)
        love.graphics.circle("line", self.x, drawY, self.r + pulse)
        -- 核心高光球體
        love.graphics.setColor(255/255, 245/255, 220/255, 1)
        love.graphics.circle("fill", self.x, drawY, self.r)
    else
        -- 道具穿透狀態光環
        if self.isPenetrating then
            love.graphics.setColor(constants.POWERUP_TYPES.PIERCE.color)
            love.graphics.circle("line", self.x, drawY, self.r + 3)
        end
        
        -- 一般球體本體
        love.graphics.setColor(constants.MORANDI_COLORS.ball)
        love.graphics.circle("fill", self.x, drawY, self.r)
    end
end

return Ball
