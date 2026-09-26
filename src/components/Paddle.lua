-- src/components/Paddle.lua
local constants = require("src.constants")
local Paddle = {}
Paddle.__index = Paddle

function Paddle.new()
    local self = setmetatable({}, Paddle)
    self.base_w = 80
    self.w = self.base_w
    self.target_w = self.base_w
    self.h = 10
    self.x = (constants.GRID_WIDTH * constants.TILE_SIZE) / 2 - self.w / 2
    self.original_y = (constants.GRID_HEIGHT * constants.TILE_SIZE) - 20
    self.y = self.original_y
    self.dy = 0 -- 速度
    self.speed = 250
    self.is_slamming = false
    self.slam_window_timer = 0
    self.hasLaser = false
    self.expandLevel = 0
    self.chargeRatio = 0 -- 洛克人蓄力進度 (0.0 ~ 1.0)
    return self
end

function Paddle:reset()
    self.target_w = self.base_w
    self.w = self.base_w
    self.x = (constants.GRID_WIDTH * constants.TILE_SIZE) / 2 - self.w / 2
    self.y = self.original_y
    self.dy = 0
    self.is_slamming = false
    self.slam_window_timer = 0
    self.hasLaser = false
    self.expandLevel = 0
    self.chargeRatio = 0
end

function Paddle:expand()
    local step = constants.PADDLE_EXPAND_STEP or 30
    local maxW = constants.PADDLE_MAX_WIDTH or (constants.GRID_WIDTH * constants.TILE_SIZE)
    self.expandLevel = self.expandLevel + 1
    self.target_w = math.min(maxW, self.base_w + self.expandLevel * step)
end

function Paddle:shrinkToBase()
    self.expandLevel = 0
    self.target_w = self.base_w
end

function Paddle:update(dt)
    -- 平滑寬度插值 (加長道具過渡)
    if math.abs(self.w - self.target_w) > 0.5 then
        local oldCenterX = self.x + self.w / 2
        self.w = self.w + (self.target_w - self.w) * math.min(1, dt * 10)
        self.x = oldCenterX - self.w / 2
    else
        self.w = self.target_w
    end

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
    local oy = gridOffsetY or 0
    local drawY = self.y + oy
    
    -- 板子本體
    love.graphics.setColor(constants.MORANDI_COLORS.paddle)
    love.graphics.rectangle("fill", self.x, drawY, self.w, self.h, 2, 2)
    
    -- 加長狀態微光邊框
    if self.target_w > self.base_w then
        if self.target_w >= (constants.PADDLE_MAX_WIDTH or 200) then
            -- 滿版無敵金色邊框
            love.graphics.setColor(constants.POWERUP_TYPES.LASER.color)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", self.x - 1, drawY - 1, self.w + 2, self.h + 2, 3, 3)
            love.graphics.setLineWidth(1)
        else
            love.graphics.setColor(constants.POWERUP_TYPES.LONG.color)
            love.graphics.setLineWidth(1)
            love.graphics.rectangle("line", self.x - 1, drawY - 1, self.w + 2, self.h + 2, 3, 3)
        end
    end
    
    -- 雷射發射砲管 (左右兩側的精緻砲台)
    if self.hasLaser then
        love.graphics.setColor(constants.POWERUP_TYPES.LASER.color)
        -- 左砲台
        love.graphics.rectangle("fill", self.x + 3, drawY - 4, 4, 4, 1, 1)
        -- 右砲台
        love.graphics.rectangle("fill", self.x + self.w - 7, drawY - 4, 4, 4, 1, 1)
        
        -- 砲口微光亮點
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.rectangle("fill", self.x + 4, drawY - 5, 2, 2)
        love.graphics.rectangle("fill", self.x + self.w - 6, drawY - 5, 2, 2)
    end
    
    -- 洛克人模式：板子環繞跑馬燈發光 (按住空白鍵蓄力)
    if self.chargeRatio and self.chargeRatio > 0 then
        local ratio = math.min(1, self.chargeRatio)
        local isFull = (ratio >= 1.0)
        local t = love.timer.getTime()
        
        -- 周長與邊界幾何
        local padX = self.x - 2
        local padY = drawY - 2
        local padW = self.w + 4
        local padH = self.h + 4
        local perimeter = 2 * (padW + padH)
        
        -- 跑馬燈速度：滿氣時疾速狂飆
        local speed = isFull and 320 or (100 + 120 * ratio)
        local baseOffset = (t * speed) % perimeter
        
        -- 外圍動態微光輪廓框
        if isFull then
            -- 滿氣洛克人經典高頻調色盤 (電光藍 / 能量綠 / 亮白 交替切換)
            local paletteIndex = math.floor(t * 18) % 3
            local r, g, b
            if paletteIndex == 0 then
                r, g, b = 100/255, 220/255, 255/255
            elseif paletteIndex == 1 then
                r, g, b = 120/255, 255/255, 180/255
            else
                r, g, b = 1, 1, 1
            end
            love.graphics.setColor(r, g, b, 0.75)
            love.graphics.setLineWidth(1.5)
            love.graphics.rectangle("line", padX, padY, padW, padH, 3, 3)
        else
            love.graphics.setColor(136/255, 186/255, 218/255, 0.3 + 0.4 * ratio)
            love.graphics.setLineWidth(1)
            love.graphics.rectangle("line", padX, padY, padW, padH, 2, 2)
        end
        love.graphics.setLineWidth(1)
        
        -- 沿著邊界順時針流動的跑馬燈光點 (Marquee Lights)
        local numLights = 10
        for i = 0, numLights - 1 do
            local dist = (baseOffset + i * (perimeter / numLights)) % perimeter
            local lx, ly
            if dist < padW then
                lx = padX + dist
                ly = padY
            elseif dist < padW + padH then
                lx = padX + padW
                ly = padY + (dist - padW)
            elseif dist < 2 * padW + padH then
                lx = padX + padW - (dist - (padW + padH))
                ly = padY + padH
            else
                lx = padX
                ly = padY + padH - (dist - (2 * padW + padH))
            end
            
            if isFull then
                local lightColorIdx = (i + math.floor(t * 20)) % 3
                if lightColorIdx == 0 then
                    love.graphics.setColor(120/255, 230/255, 255/255, 0.95)
                elseif lightColorIdx == 1 then
                    love.graphics.setColor(140/255, 255/255, 200/255, 0.95)
                else
                    love.graphics.setColor(1, 1, 1, 1)
                end
                love.graphics.circle("fill", lx, ly, 2.2)
            else
                love.graphics.setColor(150/255, 220/255, 255/255, 0.4 + 0.5 * ratio)
                love.graphics.circle("fill", lx, ly, 1.5)
            end
        end
    end
end

return Paddle
