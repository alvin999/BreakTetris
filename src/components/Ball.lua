-- src/components/Ball.lua
local constants = require("src.constants")
local utils = require("src.utils")
local Ball = {}
Ball.__index = Ball

function Ball.new()
    local self = setmetatable({}, Ball)
    self.r = 5
    self:reset()
    return self
end

function Ball:reset()
    self.x = (constants.GRID_WIDTH * constants.TILE_SIZE) / 2
    self.y = (constants.GRID_HEIGHT * constants.TILE_SIZE) / 2
    self.dx = (math.random() > 0.5 and 1 or -1) * 150
    self.dy = -150
end

function Ball:update(dt, paddle, grid)
    local oldX, oldY = self.x, self.y
    local newX = oldX + self.dx * dt
    local newY = oldY + self.dy * dt
    
    local gameAreaWidth = constants.GRID_WIDTH * constants.TILE_SIZE
    local gameAreaHeight = constants.GRID_HEIGHT * constants.TILE_SIZE
    
    -- 1. 牆壁反彈
    if newX - self.r < 0 or newX + self.r > gameAreaWidth then
        self.dx = -self.dx
        newX = oldX + self.dx * dt
    end
    if newY - self.r < 0 then
        self.dy = -self.dy
        newY = oldY + self.dy * dt
    end
    
    -- 出界檢查 (Game Over)
    if newY + self.r > gameAreaHeight then
        return "DROP"
    end
    
    -- 2. 板子碰撞 (Paddle Collision)
    if self.dy > 0 then
        local collision_y = paddle.original_y
        local y_overlap = (newY + self.r >= collision_y) and (newY - self.r <= collision_y + paddle.h)
        local x_overlap = (newX + self.r >= paddle.x) and (newX - self.r <= paddle.x + paddle.w)
        local coming_from_above = (oldY + self.r <= collision_y)
        
        if y_overlap and x_overlap and coming_from_above then
            self.y = collision_y - self.r
            self.dy = -math.abs(self.dy)
            
            -- 加速擊打
            if paddle.slam_window_timer > 0 then
                self.dy = self.dy * 1.5
                paddle.slam_window_timer = 0
            end
            
            utils.limitBallSpeed(self, constants.BALL_MAX_SPEED)
            newY = self.y -- 更新預測位置
            -- 回傳事件讓外部播放音效
            return "PADDLE_HIT"
        end
    end
    
    -- 3. 磚塊碰撞 (Grid Collision)
    local ballTileX = math.floor(newX / constants.TILE_SIZE) + 1
    local ballTileY = math.floor(newY / constants.TILE_SIZE) + 1
    
    local hit_brick = false
    -- 檢查球周圍的網格
    for row = math.max(1, ballTileY - 1), math.min(constants.GRID_HEIGHT, ballTileY + 1) do
        for col = math.max(1, ballTileX - 1), math.min(constants.GRID_WIDTH, ballTileX + 1) do
            if grid.data[row] and grid.data[row][col] ~= 0 then
                local tileX = (col - 1) * constants.TILE_SIZE
                local tileY = (row - 1) * constants.TILE_SIZE
                
                if newX + self.r > tileX and newX - self.r < tileX + constants.TILE_SIZE and
                   newY + self.r > tileY and newY - self.r < tileY + constants.TILE_SIZE then
                   
                    -- 銷毀磚塊
                    grid.data[row][col] = 0
                    
                    -- 反彈
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
                    hit_brick = "BRICK_HIT"
                    break
                end
            end
        end
        if hit_brick then break end
    end
    
    self.x = newX
    self.y = newY
    return hit_brick or "NONE"
end

function Ball:draw(gridOffsetY)
    love.graphics.setColor(constants.MORANDI_COLORS.ball)
    love.graphics.circle("fill", self.x, self.y + (gridOffsetY or 0), self.r)
end

return Ball
