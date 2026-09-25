-- src/components/Laser.lua
local constants = require("src.constants")

local Laser = {}
Laser.__index = Laser

function Laser.new(x, y)
    local self = setmetatable({}, Laser)
    self.w = 3
    self.h = 10
    self.x = x - self.w / 2
    self.y = y
    self.vy = -450
    return self
end

function Laser:update(dt, grid)
    self.y = self.y + self.vy * dt
    
    -- 磚塊碰撞檢測
    if self.y < 0 then
        return "OUT"
    end
    
    local tileCol = math.floor((self.x + self.w / 2) / constants.TILE_SIZE) + 1
    local tileRow = math.floor(self.y / constants.TILE_SIZE) + 1
    
    if tileRow >= 1 and tileRow <= grid.height and tileCol >= 1 and tileCol <= grid.width then
        local cellType = grid.data[tileRow][tileCol]
        if cellType ~= 0 then
            grid.data[tileRow][tileCol] = 0
            return {
                hit = true,
                row = tileRow,
                col = tileCol,
                tileType = cellType,
                x = (tileCol - 0.5) * constants.TILE_SIZE,
                y = (tileRow - 0.5) * constants.TILE_SIZE
            }
        end
    end
    
    return nil
end

function Laser:draw(gridOffsetY)
    local oy = gridOffsetY or 0
    love.graphics.setColor(constants.POWERUP_TYPES.LASER.color)
    love.graphics.rectangle("fill", self.x, self.y + oy, self.w, self.h, 1, 1)
    
    -- 核心亮白光
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.rectangle("fill", self.x + 1, self.y + oy, 1, self.h)
end

return Laser
