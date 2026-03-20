-- src/utils.lua
local utils = {}

-- 輔助函式：旋轉方塊 (Rotate piece)
function utils.rotate(shape)
    local size = #shape
    local newShape = {}
    for i = 1, size do
        newShape[i] = {}
        for j = 1, size do
            newShape[i][j] = shape[size - j + 1][i]
        end
    end
    return newShape
end

-- 輔助函式：碰撞偵測 (Check for collisions)
-- 需要傳入目前的網格 (grid) 以及網格寬度與高度
function utils.checkCollision(x, y, shape, grid, gridWidth, gridHeight)
    if not shape then return false end
    for row = 1, #shape do
        for col = 1, #shape[row] do
            if shape[row][col] == 1 then
                local gx = x + col - 1 -- X 座標是 1-based
                local gy = y + row - 1 -- Y 座標也是 1-based
                
                -- 邊界檢查
                if gx < 1 or gx > gridWidth or gy > gridHeight then
                    return true
                end
                
                -- 與網格內已有方塊的碰撞
                if gy >= 1 and grid[gy] and grid[gy][gx] ~= 0 then
                    return true
                end
            end
        end
    end
    return false
end

-- 🌟 新增：計算預覽方塊的位置
function utils.calculateGhostPiecePosition(piece, grid, gridWidth, gridHeight)
    if not piece or not piece.shape then return nil end
    
    local ghostY = piece.y
    -- 持續向下檢查，直到碰撞為止
    while not utils.checkCollision(piece.x, ghostY + 1, piece.shape, grid, gridWidth, gridHeight) do
        ghostY = ghostY + 1
    end
    return ghostY
end

-- 輔助函式：限制球的速度
function utils.limitBallSpeed(ball, maxSpeed)
    local speed = math.sqrt(ball.dx * ball.dx + ball.dy * ball.dy)
    if speed > maxSpeed then
        local ratio = maxSpeed / speed
        ball.dx = ball.dx * ratio
        ball.dy = ball.dy * ratio
    end
end

return utils
