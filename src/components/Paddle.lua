-- src/components/Paddle.lua
local constants = require("src.constants")
local Paddle = {}
Paddle.__index = Paddle

function Paddle.new()
    local self = setmetatable({}, Paddle)
    self.w = 80
    self.h = 10
    self.x = (constants.GRID_WIDTH * constants.TILE_SIZE) / 2 - self.w / 2
    self.original_y = (constants.GRID_HEIGHT * constants.TILE_SIZE) - 20
    self.y = self.original_y
    self.dy = 0 -- 速度
    self.speed = 250
    self.is_slamming = false
    self.slam_window_timer = 0
    return self
end

function Paddle:reset()
    self.x = (constants.GRID_WIDTH * constants.TILE_SIZE) / 2 - self.w / 2
    self.y = self.original_y
    self.dy = 0
    self.is_slamming = false
    self.slam_window_timer = 0
end

function Paddle:update(dt)
    -- 更新位置
    self.x = self.x + self.dy * dt
    
    -- 邊界限制
    local maxX = (constants.GRID_WIDTH * constants.TILE_SIZE) - self.w
    if self.x < 0 then self.x = 0 end
    if self.x > maxX then self.x = maxX end
    
    -- 衝擊狀態
    if self.is_slamming then
        self.y = self.original_y + constants.SLAM_OFFSET
    else
        self.y = self.original_y
    end
    
    -- 加速窗口計時
    if self.slam_window_timer > 0 then
        self.slam_window_timer = self.slam_window_timer - dt
    end
end

function Paddle:draw(gridOffsetY)
    love.graphics.setColor(constants.MORANDI_COLORS.paddle)
    love.graphics.rectangle("fill", self.x, self.y + (gridOffsetY or 0), self.w, self.h)
end

return Paddle
