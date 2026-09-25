-- src/components/PowerUp.lua
local constants = require("src.constants")
local ResourceManager = require("src.managers.ResourceManager")

local PowerUp = {}
PowerUp.__index = PowerUp

function PowerUp.new(x, y, typeKey)
    local self = setmetatable({}, PowerUp)
    local info = constants.POWERUP_TYPES[typeKey]
    self.typeKey = typeKey
    self.info = info
    self.w = constants.POWERUP_WIDTH
    self.h = constants.POWERUP_HEIGHT
    self.x = x - self.w / 2
    self.y = y - self.h / 2
    self.vy = constants.POWERUP_FALL_SPEED
    self.pulseTimer = 0
    return self
end

function PowerUp:update(dt)
    self.y = self.y + self.vy * dt
    self.pulseTimer = self.pulseTimer + dt * 4
end

function PowerUp:checkCollision(paddle)
    local overlapX = (self.x + self.w >= paddle.x) and (self.x <= paddle.x + paddle.w)
    local overlapY = (self.y + self.h >= paddle.y) and (self.y <= paddle.y + paddle.h)
    return overlapX and overlapY
end

function PowerUp:isOutOfBounds()
    return self.y > constants.GAME_HEIGHT
end

function PowerUp:draw(gridOffsetY)
    local oy = gridOffsetY or 0
    local drawY = self.y + oy
    
    -- 呼吸微光效果
    local pulse = 0.9 + 0.1 * math.sin(self.pulseTimer)
    local color = self.info.color
    
    -- 膠囊深色襯底，避免與背景融合
    love.graphics.setColor(20/255, 24/255, 28/255, 0.8)
    love.graphics.rectangle("fill", self.x - 1, drawY - 1, self.w + 2, self.h + 2, 4, 4)

    -- 膠囊本體 (莫蘭迪色圓角矩形)
    love.graphics.setColor(color[1] * pulse, color[2] * pulse, color[3] * pulse, 0.98)
    love.graphics.rectangle("fill", self.x, drawY, self.w, self.h, 3, 3)
    
    -- 膠囊頂部細微高光
    love.graphics.setColor(1, 1, 1, 0.45)
    love.graphics.rectangle("fill", self.x + 2, drawY + 1, self.w - 4, 2, 1, 1)

    -- 膠囊邊框
    love.graphics.setColor(1, 1, 1, 0.7)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", self.x, drawY, self.w, self.h, 3, 3)
    
    -- 居中代碼文字 (使用固定小字體，白色文字 + 黑色陰影，清晰俐落)
    local prevFont = love.graphics.getFont()
    local itemFont = ResourceManager.itemFont or prevFont
    if itemFont then
        love.graphics.setFont(itemFont)
        local text = self.info.code
        local tw = itemFont:getWidth(text)
        local th = itemFont:getHeight()
        local tx = math.floor(self.x + (self.w - tw) / 2)
        local ty = math.floor(drawY + (self.h - th) / 2)
        
        -- 文字深色陰影
        love.graphics.setColor(0, 0, 0, 0.85)
        love.graphics.print(text, tx + 1, ty + 1)
        
        -- 白色清晰主字
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(text, tx, ty)
        
        -- 還原先前字體
        if prevFont then
            love.graphics.setFont(prevFont)
        end
    end
end

return PowerUp
