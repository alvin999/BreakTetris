-- src/components/Grid.lua
local constants = require("src.constants")
local Grid = {}
Grid.__index = Grid

function Grid.new()
    local self = setmetatable({}, Grid)
    self.width = constants.GRID_WIDTH
    self.height = constants.GRID_HEIGHT
    self.tileSize = constants.TILE_SIZE
    self.data = {}
    self:reset()
    return self
end

function Grid:reset()
    for row = 1, self.height do
        self.data[row] = {}
        for col = 1, self.width do
            self.data[row][col] = 0
        end
    end
end

-- 鎖定方塊到網格
function Grid:lockPiece(piece)
    if not piece or not piece.shape then return false end
    
    local gameOver = false
    for row = 1, #piece.shape do
        for col = 1, #piece.shape[row] do
            if piece.shape[row][col] == 1 then
                local gx = piece.x + col - 1
                local gy = piece.y + row - 1
                
                if gy < 1 then
                    gameOver = true
                elseif gy <= self.height then
                    self.data[gy][gx] = piece.type
                end
            end
        end
    end
    return gameOver
end

-- 檢查並消除完成的行
function Grid:checkLines()
    local linesCleared = 0
    local newGridData = {}
    
    for row = self.height, 1, -1 do
        local isFull = true
        for col = 1, self.width do
            if self.data[row][col] == 0 then
                isFull = false
                break
            end
        end
        
        if isFull then
            linesCleared = linesCleared + 1
        else
            table.insert(newGridData, 1, self.data[row])
        end
    end
    
    -- 填補頂部空行
    while #newGridData < self.height do
        local emptyRow = {}
        for col = 1, self.width do emptyRow[col] = 0 end
        table.insert(newGridData, 1, emptyRow)
    end
    
    self.data = newGridData
    return linesCleared
end

function Grid:draw(gridOffsetY)
    for row = 1, self.height do
        for col = 1, self.width do
            local cellType = self.data[row][col]
            if cellType ~= 0 then
                local x = (col - 1) * self.tileSize
                local y = (row - 1) * self.tileSize + (gridOffsetY or 0)
                
                -- 繪製填充矩形
                local color = constants.MORANDI_COLORS[cellType] or {1, 1, 1, 1}
                love.graphics.setColor(color)
                love.graphics.rectangle("fill", x, y, self.tileSize, self.tileSize)
                
                -- 繪製邊框
                love.graphics.setColor(constants.MORANDI_COLORS.background)
                love.graphics.rectangle("line", x, y, self.tileSize, self.tileSize)
            end
        end
    end
    
    -- 繪製邊框
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("line", 0, 0, self.width * self.tileSize, self.height * self.tileSize)
end

return Grid
