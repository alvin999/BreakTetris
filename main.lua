-- ===================================
-- 程式夥伴：Lua (LÖVE/Love2D) 混和模式遊戲
-- 模式：俄羅斯方塊 (Tetris) & 打磚塊 (Breakout)
-- ===================================

-- 參數配置 (參數化)
local GRID_WIDTH = 10    -- 網格寬度 (格)
local GRID_HEIGHT = 20   -- 網格高度 (格)
local TILE_SIZE = 20     -- 每個方塊的像素大小 (px)
local SLAM_OFFSET = 5 -- 板子按下空白鍵時向下移動的像素量 (px)
local SLAM_WINDOW_DURATION = 0.2 -- 200毫秒的擊打加速窗口 (秒)
local BALL_MAX_SPEED = 1000 -- 球的最大速度 (像素/秒)

local INFO_WIDTH = 150   -- 新增：資訊顯示區寬度
local GAME_WIDTH = GRID_WIDTH * TILE_SIZE + INFO_WIDTH -- 遊戲內容的設計寬度 (400 + 150 = 550)
local GAME_HEIGHT = GRID_HEIGHT * TILE_SIZE            -- 遊戲內容的設計高度 (400)

local WINDOW_WIDTH = GAME_WIDTH    -- 初始視窗寬度使用設計寬度
local WINDOW_HEIGHT = GAME_HEIGHT  -- 初始視窗高度使用設計高度

-- 莫蘭迪色系 (低飽和度、柔和的色彩)
local MORANDI_COLORS = {
    -- 灰藍 (背景)
    background = {40/255, 46/255, 50/255, 1},
    -- 方塊顏色 (RGB/255)
    I = {149/255, 172/255, 173/255, 1}, -- 淺灰藍
    O = {173/255, 151/255, 126/255, 1}, -- 暖灰褐
    T = {136/255, 142/255, 151/255, 1}, -- 灰藍紫
    L = {181/255, 169/255, 147/255, 1}, -- 灰米黃
    J = {141/255, 164/255, 155/255, 1}, -- 灰綠
    S = {167/255, 173/255, 175/255, 1}, -- 淺灰
    Z = {156/255, 146/255, 155/255, 1}, -- 灰紫
    -- 板子/球
    paddle = {210/255, 210/255, 210/255, 1}, -- 亮灰
    ball = {230/255, 150/255, 150/255, 1},   -- 柔和紅
}

-- 字體物件
local mainFont

-- 🌟 新增：音效資源
local sounds = {}

-- 遊戲狀態
local gameState = {
    mode = "TETRIS", -- "TETRIS" 或 "BREAKOUT"
    
    -- 🌟 擴充：遊戲流程狀態
    state = "TITLE", -- "TITLE", "PLAYING", "PAUSED", "GAME_OVER"
    soundEnabled = true, -- 🌟 新增：音效開關
    grid = {},       -- 遊戲網格，儲存固定的方塊顏色
    currentPiece = nil, -- 當前下落的俄羅斯方塊
    showGhostPiece = true, -- 🌟 新增：是否顯示預覽方塊
    nextPiece = nil,    -- 下一個方塊
    isSoftDropping = false, -- <--- 新增：追蹤向下鍵是否被按住
    -- 新增：水平移動追蹤
    moveDirection = 0, -- -1: 左, 1: 右, 0: 靜止
    moveTimer = -0.15,    -- 水平移動計時器：將初始值設為負值，例如 -0.15 秒的延遲 (DAS)
    moveInterval = 0.05,  -- 新增：持續移動的間隔時間 (秒)
    --
    pieceTimer = 0,     -- 下落計時器
    score = 0,
    -- 🌟 新增：鎖定延遲 (Lock Delay)
    lockTimer = 0,
    lockDelay = 0.5, -- 0.5 秒的鎖定延遲
    -- 🌟 新增：等級與行數
    level = 1,
    lines = 0,
    -- 打磚塊變數
    paddle = { 
        x = WINDOW_WIDTH / 2 - 40, 
        y = WINDOW_HEIGHT - 20,
        w = 80, 
        h = 10,
        dy = 0,
        original_y = WINDOW_HEIGHT - 20,
        
    },
    ball = { x = WINDOW_WIDTH / 2, y = WINDOW_HEIGHT / 2, r = 5, dx = 100, dy = 100 },
    breakoutTiles = 0, 
    is_slam_released = false, -- 新增：追蹤空白鍵是否剛被釋放
    slam_window_timer = 0,   -- 🌟 新增：用於控制加速擊打的時間窗口
    -- 新增：動畫狀態變數
    isAnimating = false,       -- 是否正在播放切換動畫
    animationTimer = 0,        -- 動畫計時器
    animationDuration = 0.5,   -- 動畫持續時間 (秒)
    
    startGridY = 0,            -- 動畫起始 Y 座標
    targetGridY = 0,           -- 動畫目標 Y 座標
}

-- 俄羅斯方塊定義 (Shapes & Rotations)
local PIECES = {
    I = { { {0,0,0,0}, {1,1,1,1}, {0,0,0,0}, {0,0,0,0} } },
    O = { { {1,1}, {1,1} } },
    T = { { {0,1,0}, {1,1,1}, {0,0,0} } },
    L = { { {0,0,1}, {1,1,1}, {0,0,0} } },
    J = { { {1,0,0}, {1,1,1}, {0,0,0} } },
    S = { { {0,1,1}, {1,1,0}, {0,0,0} } },
    Z = { { {1,1,0}, {0,1,1}, {0,0,0} } }
}

-- 輔助函式：碰撞偵測 (Helper: Check for collisions)
local function checkCollision(x, y, shape)
    if not shape then return false end
    for row = 1, #shape do
        for col = 1, #shape[row] do
            if shape[row][col] == 1 then
                local gx = x + col - 1 -- X 座標是 1-based
                local gy = y + row - 1 -- Y 座標也是 1-based
                -- 🌟 核心修正：分離邊界檢查，允許頂部緩衝區
                -- 1. 嚴格檢查左右邊界
                if gx < 1 or gx > GRID_WIDTH then
                    return true
                end
                -- 2. 嚴格檢查底部邊界 (1-based)
                if gy > GRID_HEIGHT then
                    return true
                end
                -- 3. 只在網格內部 (gy >= 1) 檢查與其他方塊的碰撞
                if gy >= 1 and gameState.grid[gy] and gameState.grid[gy][gx] ~= 0 then
                    return true
                end
            end
        end
    end
    return false
end

-- 俄羅斯方塊輔助函式：旋轉方塊 (Helper: Rotate piece)
local function rotate(shape)
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

-- 🌟 新增：計算預覽方塊的位置
local function calculateGhostPiecePosition(piece)
    if not piece or not piece.shape then return nil end
    
    local ghostY = piece.y
    -- 持續向下檢查，直到碰撞為止
    while not checkCollision(piece.x, ghostY + 1, piece.shape) do
        ghostY = ghostY + 1
    end
    return ghostY
end

-- 生成新方塊 (Spawn New Piece)
local function spawnNewPiece()
    local pieceType = gameState.nextPiece or "I" -- 初始使用 I
    local shapes = PIECES[pieceType]
    local shape = shapes[1]
    local x = math.floor((GRID_WIDTH - #shape[1]) / 2) + 1
    
    gameState.currentPiece = {
        type = pieceType,
        shape = shape,
        x = x,
        y = 0,  -- 🌟 座標系統恢復：Y 軸為 1-based。y=0 代表網格頂部之上的緩衝區
        color = MORANDI_COLORS[pieceType] or {1, 1, 1, 1} -- 🌟 修正：增加後備顏色(白色)，避免 nil
    }
    
    -- 決定下一個方塊
    local pieceTypes = {"I", "O", "T", "L", "J", "S", "Z"}
    gameState.nextPiece = pieceTypes[math.random(#pieceTypes)]
end

-- 🌟 重構：前向宣告 (Forward-declare) 函式以解決順序依賴
local checkLines
local playSound -- 🌟 新增：前向宣告 playSound 函式

-- 鎖定方塊到網格 (Lock Piece to Grid)
-- 🌟 重構：將函式改為 local
local function lockPiece()
    local piece = gameState.currentPiece
    -- 🌟 修正：增加 nil 檢查，確保函式在任何情況下都是安全的
    playSound("lock")
    if not piece then
        return
    end
    for row = 1, #piece.shape do
        for col = 1, #piece.shape[row] do
            if piece.shape[row][col] == 1 then
                local gx = piece.x + col - 1
                local gy = piece.y + row - 1 -- Y 座標是 1-based
                -- 🌟 修正：新增遊戲結束條件，如果方塊鎖定在網格之上
                if gy < 1 then
                    print("Game Over! Piece locked above grid.")
                    gameState.state = "GAME_OVER"
                    return -- 立即返回，不執行後續鎖定
                elseif gy <= GRID_HEIGHT then
                    gameState.grid[gy][gx] = piece.type
                end
            end
        end
    end
    
    -- 🌟 修正：重置與當前方塊相關的移動狀態，避免影響下一個方塊
    gameState.isSoftDropping = false
    gameState.moveDirection = 0
    gameState.moveTimer = 0
    gameState.lockTimer = 0 -- 🌟 修正：鎖定後重置鎖定計時器

    -- 檢查消行
    checkLines()
    -- 生成新方塊
    spawnNewPiece()
end

-- 檢查並消除完成的行 (Check and Clear Lines)
-- 🌟 重構：將函式改為 local
checkLines = function()
    local linesCleared = 0
    local tempGrid = {} 
    
    -- 從底向上檢查
    for row = GRID_HEIGHT, 1, -1 do
        local isFull = true
        
        -- 檢查該行是否存在
        if not gameState.grid[row] then
            isFull = false
        else
            for col = 1, GRID_WIDTH do
                if gameState.grid[row][col] == 0 then
                    isFull = false
                    break
                end
            end
        end
        
        if isFull then
            linesCleared = linesCleared + 1
        elseif gameState.grid[row] then
            -- 如果行未滿，將它儲存到 tempGrid (確保只儲存存在的行)
            table.insert(tempGrid, 1, gameState.grid[row]) 
        end
    end

    -- 🌟 修正：只有在消行時才更新分數和等級
    if linesCleared > 0 then
        playSound("clear")
        gameState.score = gameState.score + linesCleared * 100
        gameState.lines = gameState.lines + linesCleared
        
        -- 每 10 行升一級
        local newLevel = math.floor(gameState.lines / 10) + 1
        gameState.level = math.min(newLevel, 100) -- 等級上限為 100

        -- 填充頂部空行
        for i = 1, linesCleared do
            table.insert(tempGrid, 1, {0,0,0,0,0,0,0,0,0,0})
        end
    end
    
    -- 🌟 修正：確保網格總是完整的，補足頂部的空行
    local numRows = #tempGrid
    for i = 1, GRID_HEIGHT - numRows do
        table.insert(tempGrid, 1, {0,0,0,0,0,0,0,0,0,0}) -- 保持 10 個 0
    end

    gameState.grid = tempGrid
end

-- 打磚塊輔助函式：切換到打磚塊模式 (Switch to Breakout Mode)
-- 🌟 重構：將函式改為 local
local function switchToBreakout()
    print("開始切換動畫：Tetris -> Breakout")
    gameState.currentPiece = nil -- 停止方塊下落
    
    -- **修正：將數據獲取邏輯移回函式內部**
    local currentGrid = gameState.grid
    local rowsToKeep = {}
    
    -- 找出所有非空行
    for row = 1, GRID_HEIGHT do
        local hasTile = false
        if currentGrid[row] then -- 必須檢查行是否存在
            for col = 1, GRID_WIDTH do
                if currentGrid[row][col] ~= 0 then
                    hasTile = true
                    break
                end
            end
        end
        if hasTile then
            table.insert(rowsToKeep, currentGrid[row])
        end
    end
    
    local numRowsToKeep = #rowsToKeep
    local brickWallHeight = numRowsToKeep * TILE_SIZE
    -- **如果沒有方塊，直接返回，不啟動動畫**
    if numRowsToKeep == 0 then
        print("沒有方塊可轉換，保持 Tetris 模式。")
    end
    
    -- 設置動畫參數
    gameState.isAnimating = true
    gameState._anim_targetMode = "BREAKOUT"
    gameState.animationTimer = 0
    -- 磚牆在 Tetris 網格中已經處於靜止狀態，故起始偏移量為 0。
    gameState.startGridY = 0
    -- 上推到磚牆高度。
    local totalHeight = GRID_HEIGHT * TILE_SIZE
    gameState.targetGridY = -(totalHeight - brickWallHeight)
    
    -- 儲存磚塊數據以供動畫結束時使用(即使是空的也要儲存)
    gameState._anim_rowsToKeep = rowsToKeep
    gameState._anim_numRowsToKeep = numRowsToKeep

    -- **🌟 關鍵修正：確保 love.draw 在動畫期間繪製的是 rowsToKeep**
    -- 我們將使用一個臨時變數來儲存動畫期間的網格，避免直接修改主網格。
    gameState._anim_grid = {}
    -- 在動畫開始時，將目前的 grid 複製到 _anim_grid (1-based)
    for row = 1, GRID_HEIGHT do
        gameState._anim_grid[row] = gameState.grid[row]
    end

    -- 修正 switchToBreakout 函式內，if numRowsToKeep == 0 的快速通道
    if numRowsToKeep == 0 then
        gameState.isAnimating = false
        
        -- **修正：確保網格是一個完整的 2D 表格，即使是空的**
        local emptyGrid = {} -- 1-based
        for row = 1, GRID_HEIGHT do
            emptyGrid[row] = {}
            for col = 1, GRID_WIDTH do
                emptyGrid[row][col] = 0
            end
        end
        gameState.grid = emptyGrid 
        
        gameState.breakoutTiles = 0 
        gameState.mode = "BREAKOUT" 
        
        -- ... (初始化球和板子的邏輯保持不變)
        
        return -- 立即返回，跳過動畫邏輯
    end

    
end

-- 打磚塊輔助函式：切換回俄羅斯方塊模式 (Switch back to Tetris Mode)
-- 🌟 重構：將函式改為 local
local function switchToTetris()
    print("開始切換動畫：Breakout -> Tetris")

    -- **修正：將數據獲取邏輯移回函式內部**
    local currentGrid = gameState.grid
    local rowsToKeep = {}
    
    -- 找出所有非空行 (現在的磚牆)
    for row = 1, GRID_HEIGHT do
        local hasTile = false
        for col = 1, GRID_WIDTH do
            if currentGrid[row] and currentGrid[row][col] ~= 0 then
                hasTile = true
                break
            end
        end
        if hasTile then
            table.insert(rowsToKeep, currentGrid[row])
        end
    end

    local numRowsToKeep = #rowsToKeep
    
    -- 設置動畫參數
    gameState.isAnimating = true
    gameState._anim_targetMode = "TETRIS"
    gameState.animationTimer = 0
    gameState.startGridY = 0 -- 磚牆在 Breakout 模式下已經在頂部
    -- 目標位置：將磚塊放在底部
    gameState.targetGridY = (GRID_HEIGHT - numRowsToKeep) * TILE_SIZE
    
    -- 儲存數據
    -- 🌟 關鍵修正：在動畫開始前，就準備好下一個方塊的類型。
    -- 這確保了在動畫期間，love.draw 總能安全地讀取 nextPiece。
    local pieceTypes = {"I", "O", "T", "L", "J", "S", "Z"}
    gameState.nextPiece = pieceTypes[math.random(#pieceTypes)]
    gameState._anim_rowsToKeep = rowsToKeep
    gameState._anim_numRowsToKeep = numRowsToKeep

    -- **函式在這裡結束，模式切換交由 love.update 處理**
end

-- 遊戲重置函式：只重置遊戲數據，不影響視窗狀態
-- 🌟 重構：將函式改為 local
local function resetGame()
    print("重置遊戲數據...")
    
    -- 重置網格
    for row = 1, GRID_HEIGHT do
        gameState.grid[row] = {}
        for col = 1, GRID_WIDTH do
            gameState.grid[row][col] = 0 -- 0 表示空
        end
    end

    -- 重置分數和模式
    gameState.score = 0
    gameState.mode = "TETRIS"
    gameState.isSoftDropping = false
    gameState.moveDirection = 0
    gameState.moveTimer = 0
    gameState.level = 1
    gameState.lines = 0
    
    -- 初始化第一個方塊 (使用 nextPiece 的邏輯來確保流程正確)
    local pieceTypes = {"I", "O", "T", "L", "J", "S", "Z"}
    gameState.nextPiece = pieceTypes[math.random(#pieceTypes)]
    spawnNewPiece() -- 讓 spawnNewPiece 函式負責生成當前方塊
end

-- LÖVE 框架函式
-- 🌟 新增：播放音效的輔助函式
playSound = function(name) -- 🌟 修正：將函式賦值給已宣告的變數
    if gameState.soundEnabled and sounds[name] then
        sounds[name]:stop() -- 停止任何正在播放的同名音效，避免重疊
        sounds[name]:play()
    end
end

function love.load()
    -- 載入音效
    sounds.lock = love.audio.newSource("sounds/lock.mp3", "static")
    sounds.start = love.audio.newSource("sounds/start.mp3", "static")
    sounds.endgame = love.audio.newSource("sounds/endgame.mp3", "static")
    sounds.clear = love.audio.newSource("sounds/clear.mp3", "static")
    sounds.blip = love.audio.newSource("sounds/blip.mp3", "static")

    -- 使用新的 WINDOW_WIDTH
    love.window.setMode(WINDOW_WIDTH, WINDOW_HEIGHT) 
    
    love.window.setTitle("Tetris-Breakout Hybrid")  
    -- 初始呼叫 resetGame() 進行數據初始化
    resetGame() 
    -- 由於 resetGame() 已經呼叫了 spawnNewPiece()，所以這裡不需要再呼叫了

    -- 🌟 修正：創建一個固定大小、但帶有 "nearest" 濾鏡的清晰字體
    mainFont = love.graphics.newFont(12, "none") -- 創建一個 12px 大小、無 hinting 的字體
    mainFont:setFilter("nearest", "nearest") -- 為字體本身設定濾鏡，確保縮放時保持銳利

    -- 🌟 終極修正 (Windows 輸入法問題)：
    -- 明確告知作業系統本遊戲不需要文字輸入，從而禁用 IME (輸入法) 的干擾。
    love.keyboard.setTextInput(false)
end

function love.resize(w, h)
    -- 🌟 智慧字體渲染：當視窗大小改變時，重新生成字體以獲得最佳清晰度。
    
    -- 1. 計算新的縮放比例，與 love.draw 中的邏輯完全相同。
    local scaleX = w / GAME_WIDTH
    local scaleY = h / GAME_HEIGHT
    local scale = math.min(scaleX, scaleY)

    -- 2. 根據縮放比例計算理想的字體大小。
    -- 我們使用 12 作為基礎大小，並向上取整以獲得更平滑的結果。
    local newFontSize = math.ceil(12 * scale)

    -- 3. 重新創建字體物件。
    -- 檢查 newFontSize 是否大於 0，避免在視窗極小化時出錯。
    if newFontSize > 0 then
        print("Window resized. Recreating font with size: " .. newFontSize)
        mainFont = love.graphics.newFont(newFontSize, "none")
        mainFont:setFilter("linear", "linear") -- 使用 'linear' 濾鏡以獲得平滑的縮放效果。
    end

    -- 🌟 修正：當視窗大小改變時，校準 Breakout 模式下的物件位置，防止物件在畫面外。
    if gameState.mode == "BREAKOUT" then
        local GAME_AREA_WIDTH = GRID_WIDTH * TILE_SIZE
        local GAME_AREA_HEIGHT = GRID_HEIGHT * TILE_SIZE

        -- 1. 校準球的位置
        -- 使用 math.max 和 math.min 確保球的中心點被限制在遊戲區域內（考慮到半徑）
        gameState.ball.x = math.max(gameState.ball.r, math.min(GAME_AREA_WIDTH - gameState.ball.r, gameState.ball.x))
        gameState.ball.y = math.max(gameState.ball.r, math.min(GAME_AREA_HEIGHT - gameState.ball.r, gameState.ball.y))

        -- 2. 校準板子的位置
        -- 確保板子的左側不會超出左邊界，右側不會超出右邊界
        if gameState.paddle.x < 0 then gameState.paddle.x = 0 end
        if gameState.paddle.x + gameState.paddle.w > GAME_AREA_WIDTH then
            gameState.paddle.x = GAME_AREA_WIDTH - gameState.paddle.w
        end
    end
end

-- 輔助函式：限制球的速度
local function limitBallSpeed(ball)
    local speed = math.sqrt(ball.dx * ball.dx + ball.dy * ball.dy)
    if speed > BALL_MAX_SPEED then
        local ratio = BALL_MAX_SPEED / speed
        ball.dx = ball.dx * ratio
        ball.dy = ball.dy * ratio
    end
end

function love.update(dt)
    -- 🌟 修正：只在 PLAYING 狀態下執行遊戲物理和計時器
    if gameState.state ~= "PLAYING" then
        return
    end
    
    -- 如果正在動畫，則鎖定所有輸入和遊戲邏輯
    if gameState.isAnimating then
        gameState.animationTimer = gameState.animationTimer + dt
        local t = gameState.animationTimer / gameState.animationDuration
        
        if t >= 1 then
            -- 動畫完成！
            gameState.isAnimating = false
            
            -- 執行最終的網格結構修改
            local numRows = gameState._anim_numRowsToKeep
            local rowsToKeep = gameState._anim_rowsToKeep
            local newGrid = {}
            local targetMode = gameState._anim_targetMode 

            if targetMode == "BREAKOUT" then
                -- Tetris -> Breakout 轉換完成
                print("動畫完成：進入 Breakout 模式")
                playSound("start")
                
                -- **修正：將磚塊設置在網格頂部 (為 Breakout 模式準備)**
                for row = 1, GRID_HEIGHT do
                    if row <= numRows then
                         newGrid[row] = rowsToKeep[row]
                    else -- 底部剩餘行填充空行
                        newGrid[row] = {}
                        for col = 1, GRID_WIDTH do newGrid[row][col] = 0 end
                    end
                end
                gameState.grid = newGrid
                
                -- 正式切換模式並初始化 Breakout 元素
                gameState.mode = "BREAKOUT"
                -- 初始化板子和球的位置 (複製自 switchToBreakout 底部)
                local GAME_AREA_WIDTH = GRID_WIDTH * TILE_SIZE
                gameState.ball.x = GAME_AREA_WIDTH / 2
                gameState.ball.y = WINDOW_HEIGHT / 2
                gameState.ball.dx = (math.random() > 0.5 and 1 or -1) * 150
                gameState.ball.dy = -150
                gameState.paddle.x = GAME_AREA_WIDTH / 2 - gameState.paddle.w / 2
                gameState.paddle.y = WINDOW_HEIGHT - 20
                gameState.paddle.original_y = WINDOW_HEIGHT - 20

                -- **修正：在網格被最終設置後，重新計算磚塊數量**
                gameState.breakoutTiles = 0
                for row = 1, GRID_HEIGHT do
                    for col = 1, GRID_WIDTH do
                        if gameState.grid[row] and gameState.grid[row][col] ~= 0 then
                            gameState.breakoutTiles = gameState.breakoutTiles + 1
                        end
                    end
                end

            elseif targetMode == "TETRIS" then
                -- Breakout -> Tetris 轉換完成
                print("動畫完成：進入 Tetris 模式")
                playSound("start")
                
                -- 將磚塊設置在網格底部
                for row = 1, GRID_HEIGHT do
                    if row <= GRID_HEIGHT - numRows then
                        newGrid[row] = {}
                        for col = 1, GRID_WIDTH do newGrid[row][col] = 0 end
                    else
                        local rowsIndex = row - (GRID_HEIGHT - numRows)
                        -- 🌟 修正：增加 nil 檢查，確保在 rowsToKeep 為空時也能正確初始化
                        if rowsToKeep and rowsToKeep[rowsIndex] then
                            newGrid[row] = rowsToKeep[rowsIndex]
                        else
                            newGrid[row] = {0,0,0,0,0,0,0,0,0,0}
                        end
                    end
                end
                gameState.grid = newGrid
                
                -- 正式切換模式並生成新方塊
                gameState.mode = "TETRIS"
                spawnNewPiece()
            end

            -- 🌟 修正：先替換數據，然後在下一行關閉 isAnimating
            gameState.isAnimating = false
            gameState.animationTimer = 0 -- 重置計時器
            return -- 動畫完成，下一幀開始正常遊戲
        end
        
        -- 線性插值 (Linear Interpolation) 計算當前 Y 座標
        local t_interp = gameState.animationTimer / gameState.animationDuration
        
        -- 使用 t_interp 確保 Y 座標計算是正確的
        local currentY = gameState.startGridY + (gameState.targetGridY - gameState.startGridY) * t_interp
        gameState.currentGridY = currentY -- 儲存當前 Y 座標給 love.draw 使用
        
        return -- 鎖定遊戲邏輯
    end

    -- ===================================
    -- TETRIS 模式邏輯
    -- ===================================
    if gameState.mode == "TETRIS" then

        -- 處理水平持續移動 (ARR/DAS)
        if gameState.moveDirection ~= 0 then
            gameState.moveTimer = gameState.moveTimer + dt
            if gameState.moveTimer >= 0 then
                
                local piece = gameState.currentPiece
                if piece then -- 確保 piece 存在
                    local newX = piece.x + gameState.moveDirection
                    if not checkCollision(newX, piece.y, piece.shape) then
                        piece.x = newX
                        -- 🌟 優化：移動成功就重置鎖定計時器。這涵蓋了在地面上移動的情況，且在空中移動時重置也無害。
                        gameState.lockTimer = 0
                    end
                end

                gameState.moveTimer = gameState.moveInterval
            end
        end
        
        local piece = gameState.currentPiece
        if not piece then return end -- 安全檢查

        -- 🌟 根本性重構：確保下落和鎖定邏輯的互斥性 (The fix for the "extra drop" bug)
        -- 透過這個 if/else 結構，我們確保了遊戲只會處於以下兩種狀態之一：
        -- 1. 方塊下方有障礙物 (在地面上) -> 處理鎖定倒數計時。
        -- 2. 方塊下方是空的 (在空中) -> 處理正常下落。
        -- 這就避免了方塊觸底後，舊的「下落計時器」仍在運行並導致額外移動的 bug。
        if checkCollision(piece.x, piece.y + 1, piece.shape) then
            -- 情況 A: 方塊在地面上或與其他方塊接觸 -> 處理鎖定邏輯
            gameState.lockTimer = gameState.lockTimer + dt
            if gameState.lockTimer >= gameState.lockDelay then
                lockPiece()
                return -- 鎖定後立即返回，結束本幀的 update
            end
        else
            -- 情況 B: 方塊在空中 -> 處理下落邏輯
            gameState.lockTimer = 0 -- 只要在空中，就重置鎖定計時器
            local baseDropInterval = math.max(0.1, 1.0 - (gameState.level - 1) * 0.05)
            local dropInterval = gameState.isSoftDropping and 0.05 or baseDropInterval
            
            gameState.pieceTimer = gameState.pieceTimer + dt
            if gameState.pieceTimer >= dropInterval then 
                gameState.pieceTimer = 0
                -- 🌟 優化：移除內部的 `checkCollision`。因為外層的 `else` 已經確保了下方是空的，所以這裡的檢查是多餘的。
                piece.y = piece.y + 1
            end
        end
    -- ===================================
    -- BREAKOUT 模式邏輯
    -- ===================================
    elseif gameState.mode == "BREAKOUT" then
        local GAME_AREA_WIDTH = GRID_WIDTH * TILE_SIZE
        local paddle = gameState.paddle
        
        -- 板子 X 軸移動邏輯
        paddle.x = paddle.x + paddle.dy * dt
        -- 邊界檢查
        if paddle.x < 0 then
            paddle.x = 0
        elseif paddle.x + paddle.w > GAME_AREA_WIDTH then 
            paddle.x = GAME_AREA_WIDTH - paddle.w
        end

        local hit_brick = false

        -- **新增：Y 座標由狀態控制**
        if gameState.paddle.is_slamming then
            -- 按下狀態：板子向下壓
            paddle.y = paddle.original_y + SLAM_OFFSET
        else
            -- 釋放狀態：板子復位
            paddle.y = paddle.original_y
        end

        -- **新增：倒數計時加速擊打窗口**
        if gameState.slam_window_timer > 0 then
            gameState.slam_window_timer = gameState.slam_window_timer - dt
        end

        -- 1. 球的移動和預測座標
        local moveX = gameState.ball.dx * dt
        local moveY = gameState.ball.dy * dt
        
        local oldX = gameState.ball.x
        local oldY = gameState.ball.y
        
        local newX = oldX + moveX
        local newY = oldY + moveY
        
        -- 2. 牆壁反彈 (先處理，更新 newX/newY)
        if newX - gameState.ball.r < 0 or newX + gameState.ball.r > GAME_AREA_WIDTH then
            gameState.ball.dx = -gameState.ball.dx
            newX = oldX + gameState.ball.dx * dt
            limitBallSpeed(gameState.ball)
        end
        if newY - gameState.ball.r < 0 then
            gameState.ball.dy = -gameState.ball.dy
            newY = oldY + gameState.ball.dy * dt
            limitBallSpeed(gameState.ball)
        end
        
        if newY + gameState.ball.r > WINDOW_HEIGHT then
            print("Ball dropped! Game Over!")
            gameState.state = "GAME_OVER"
            playSound("endgame")
        end
        
        -- 3. 板子碰撞 (Paddle Collision)

        -- 僅檢查球是否向下移動 (dy > 0)
        if gameState.ball.dy > 0 then
            
            local paddle = gameState.paddle
            local r = gameState.ball.r
            
            -- **關鍵修正：使用 original_y 進行碰撞判定，避免快速按空白鍵時穿透**
            local collision_y = paddle.original_y
            
            -- **AABB 重疊碰撞檢查 (最穩定的防穿透機制)**
            -- 我們檢查球在下一幀的位置 (newX, newY) 是否與板子發生重疊。
            
            -- 1. Y軸重疊：使用 original_y 作為碰撞判定基準
            local y_overlap = (newY + r >= collision_y) and (newY - r <= collision_y + paddle.h)
            
            -- 2. X軸重疊：
            --    球的右邊 (newX + r) 必須超過板子左邊 (paddle.x) AND
            --    球的左邊 (newX - r) 必須在板子右邊內 (paddle.x + paddle.w)
            local x_overlap = (newX + r >= paddle.x) and (newX - r <= paddle.x + paddle.w)
            
            -- 3. 額外保障：確保球的上一個位置在板子上方 (使用 original_y)
            --    這確保我們只處理從上方擊打的情況，避免卡在板子底部。
            local coming_from_above = (oldY + r <= collision_y)
            
            if y_overlap and x_overlap and coming_from_above then
                
                -- **碰撞發生！**
                
                -- 步驟 1: 強制精確定位 (使用 original_y)
                -- 將球的底部精確放置在板子的原始頂部位置，消除任何重疊。
                gameState.ball.y = collision_y - r
                
                -- 步驟 2: 反彈
                gameState.ball.dy = -math.abs(gameState.ball.dy)
                playSound("blip")
                
                -- 3. 應用擊打加速效果
                if gameState.slam_window_timer > 0 then -- <--- 這裡改為檢查計時器
                    gameState.ball.dy = gameState.ball.dy * 1.5
                    paddle.slamTimer = 0
                    gameState.slam_window_timer = 0 -- 🌟 擊中後立即清除加速窗口
                end
                -- 步驟 4: 速度限制
                limitBallSpeed(gameState.ball)
                
                -- 更新 newY，確保後續的磚塊碰撞和最終賦值使用正確的 Y 座標
                newY = gameState.ball.y
            end
        end
        
        -- 4. 磚塊碰撞 (修正後的邏輯)
        local ballTileX = math.floor(gameState.ball.x / TILE_SIZE)
        local ballTileY = math.floor(gameState.ball.y / TILE_SIZE)

        -- 只檢查球周圍 3x3 的網格
        for row = math.max(1, ballTileY), math.min(GRID_HEIGHT, ballTileY + 2) do
            for col = math.max(1, ballTileX), math.min(GRID_WIDTH, ballTileX + 2) do
                if gameState.grid[row] and gameState.grid[row][col] ~= 0 then
                    local tileX = (col - 1) * TILE_SIZE
                    local tileY = (row - 1) * TILE_SIZE
                    
                    -- 🌟 修正：使用預測的 newX 和 newY 進行碰撞檢測，防止穿隧
                    if newX + gameState.ball.r > tileX and newX - gameState.ball.r < tileX + TILE_SIZE and
                       newY + gameState.ball.r > tileY and newY - gameState.ball.r < tileY + TILE_SIZE then
                        
                        -- 銷毀磚塊 (永久清空)
                        gameState.grid[row][col] = 0
                        gameState.breakoutTiles = gameState.breakoutTiles - 1
                        gameState.score = gameState.score + 50
                        
                        -- 簡單反彈
                        local centerTileX = tileX + TILE_SIZE / 2
                        local centerTileY = tileY + TILE_SIZE / 2

                        -- 🌟 修正：簡化反彈邏輯
                        local dx_from_center = newX - centerTileX
                        local dy_from_center = newY - centerTileY

                        -- 根據球擊中磚塊的相對位置決定反彈方向
                        if math.abs(dx_from_center) > math.abs(dy_from_center) then
                            -- 水平碰撞更顯著，反轉 X 速度
                            playSound("blip")
                            gameState.ball.dx = -gameState.ball.dx
                            newX = oldX + gameState.ball.dx * dt -- 修正 newX
                        else
                            -- 垂直碰撞更顯著，反轉 Y 速度
                            playSound("blip")
                            gameState.ball.dy = -gameState.ball.dy
                            newY = oldY + gameState.ball.dy * dt -- 修正 newY
                        end

                        limitBallSpeed(gameState.ball)

                        -- 檢查是否所有磚塊都被清除
                        if gameState.breakoutTiles <= 0 then
                            print("所有磚塊清除！自動切回俄羅斯方塊模式。")
                            switchToTetris()
                        end
                        
                        -- 找到碰撞後跳出循環
                        hit_brick = true
                        break 
                    end
                end
            end
            if hit_brick then break end
        end

        -- **最終位置更新：確保球移動**
        -- 這裡使用 newX/newY (包含了所有碰撞處理後的最終座標)
        gameState.ball.x = newX
        gameState.ball.y = newY

        -- **重要：清除單幀加速狀態**
        -- 確保加速只在 keyreleased 之後的一幀內有效
        if gameState.is_slam_active then
            gameState.is_slam_active = false
        end
    end
end

function love.keypressed(key, scancode)
    -- F 鍵切換全螢幕模式
    if scancode == 'f' then
        local currentFullscreen = love.window.getFullscreen()
        -- 切換全螢幕狀態，並使用 'desktop' 模式
        love.window.setFullscreen(not currentFullscreen, "desktop")
        -- 🌟 移除：不再需要手動 setMode，love.resize 會自動觸發
        return -- 處理完畢，不執行其他邏輯
    end

    -- ===================================
    -- 遊戲狀態控制
    -- ===================================
    if gameState.state == "TITLE" and scancode == "return" then -- Enter 鍵開始遊戲
        gameState.state = "PLAYING"
        playSound("start")
        return
    end

    if gameState.state == "GAME_OVER" and scancode == "return" then
        resetGame()
        gameState.state = "TITLE" -- 回到標題畫面
        return
    end
    
    if gameState.state == "PLAYING" and scancode == "p" then -- P 鍵暫停
        gameState.state = "PAUSED"
        return
    elseif gameState.state == "PAUSED" and key == "p" then -- P 鍵恢復
        gameState.state = "PLAYING"
        return
    end
    
    -- ===================================
    -- 模式切換
    -- ===================================
    -- 🌟 修正：將 G 鍵和 C 鍵的邏輯放在 state 檢查之後
    -- 確保只有在 PLAYING 狀態下才能切換模式或功能
    if gameState.state ~= "PLAYING" then
        return
    end

    -- 🌟 新增：音效開關
    if scancode == 'm' then
        gameState.soundEnabled = not gameState.soundEnabled
        return
    end

    -- 模式切換
    if scancode == 'c' then
        if gameState.mode == "TETRIS" then
            switchToBreakout()
        elseif gameState.mode == "BREAKOUT" then
            switchToTetris()
        end
        return
    end

    -- 預覽方塊顯示切換
    if scancode == 'g' then
        gameState.showGhostPiece = not gameState.showGhostPiece
        return
    end

    local piece = gameState.currentPiece
    -- ===================================
    -- TETRIS 模式控制 (上、下、左、右、Vi)
    -- ===================================
    if gameState.mode == "TETRIS" then
        -- 🌟 修正：增加對 piece 和 piece.shape 的 nil 檢查，使邏輯更健壯
        if not piece or not piece.shape then return end

        if scancode == 'left' or scancode == 'h' then
            -- 設定持續移動方向
            gameState.moveDirection = -1
            
            -- 為了即時性，可以保留按下的第一次移動
            if not checkCollision(piece.x - 1, piece.y, piece.shape) then
                piece.x = piece.x - 1
                gameState.lockTimer = 0
            end

            -- **關鍵修正**：啟動延遲計時器
            gameState.moveTimer = -0.15 -- DAS 延遲
        elseif scancode == 'right' or scancode == 'l' then
            -- 設定持續移動方向
            gameState.moveDirection = 1

            -- 為了即時性，可以保留按下的第一次移動
            if not checkCollision(piece.x + 1, piece.y, piece.shape) then
                piece.x = piece.x + 1
                gameState.lockTimer = 0
            end

            -- **關鍵修正**：啟動延遲計時器
            gameState.moveTimer = -0.15 -- DAS 延遲
        elseif scancode == 'down' or scancode == 'j' then
            -- 設置軟降狀態，不在這裡進行單次下降
            gameState.isSoftDropping = true
        elseif scancode == 'up' or scancode == 'k' then
            -- 旋轉
            local newShape = rotate(piece.shape)
            local rotated = false
            if not checkCollision(piece.x, piece.y, newShape) then
                piece.shape = newShape
                rotated = true
            -- 牆踢 (Wall Kick) 簡化實作
            elseif not checkCollision(piece.x + 1, piece.y, newShape) then
                piece.x = piece.x + 1
                piece.shape = newShape
                rotated = true
            elseif not checkCollision(piece.x - 1, piece.y, newShape) then
                piece.x = piece.x - 1
                piece.shape = newShape
                rotated = true
            end
            -- 🌟 優化：只要旋轉成功，就重置鎖定計時器。
            -- 這樣做更符合現代俄羅斯方塊的規則（任何成功的操作都會重置鎖定延遲）。
            if rotated then
                gameState.lockTimer = 0
            end
        elseif scancode == 'space' then
            -- 硬降 (Hard Drop): 直接落到底部
            while not checkCollision(piece.x, piece.y + 1, piece.shape) do
                piece.y = piece.y + 1
            end
            lockPiece() -- 硬降後立即鎖定，無需延遲
        end

    -- ===================================
    -- BREAKOUT 模式控制
    -- ===================================
    elseif gameState.mode == "BREAKOUT" then
        local paddle = gameState.paddle

        if scancode == 'left' or scancode == 'a' or scancode == 'h' then
            gameState.paddle.dy = -250 -- 板子移動速度
        elseif scancode == 'right' or scancode == 'd' or scancode == 'l' then
            gameState.paddle.dy = 250
        elseif scancode == 'space' then
             -- 板子向下衝擊力
             gameState.paddle.is_slamming = true
             
             paddle.is_slammed = true -- <--- 確保設定為 true
        end
    end
end

function love.keyreleased(key, scancode)
    if gameState.mode == "BREAKOUT" then
        if (scancode == 'left' or scancode == 'a' or scancode == 'h') and gameState.paddle.dy < 0 then
            gameState.paddle.dy = 0
        elseif (scancode == 'right' or scancode == 'd' or scancode == 'l') and gameState.paddle.dy > 0 then
            gameState.paddle.dy = 0
        elseif scancode == 'space' then
            gameState.paddle.is_slamming = false
             
            -- 修正：設置加速時間窗口，賦予 200ms 的加速機會
            gameState.slam_window_timer = SLAM_WINDOW_DURATION 
        end
    elseif gameState.mode == "TETRIS" then -- <--- 新增：Tetris 模式釋放邏輯
        if scancode == 'down' or scancode == 'j' then
            gameState.isSoftDropping = false
        end
        -- 新增：停止水平移動（按住左右放開後）
        if (scancode == 'left' or scancode == 'h') and gameState.moveDirection == -1 then
            gameState.moveDirection = 0
        elseif (scancode == 'right' or scancode == 'l') and gameState.moveDirection == 1 then
            gameState.moveDirection = 0
        end
    end
end

function love.draw()

    -- 1. 獲取當前視窗的實際尺寸
    local actualWidth, actualHeight = love.graphics.getDimensions()

    -- 2. 計算縮放比例
    local scaleX = actualWidth / GAME_WIDTH
    local scaleY = actualHeight / GAME_HEIGHT
    
    -- 使用較小的比例以保持長寬比 (等比例縮放)
    local scale = math.min(scaleX, scaleY)

    -- 3. 計算置中位移量
    local canvasWidth = GAME_WIDTH * scale
    local canvasHeight = GAME_HEIGHT * scale
    local offsetX = (actualWidth - canvasWidth) / 2
    local offsetY = (actualHeight - canvasHeight) / 2
    
    -- 4. 應用變換：移動 (置中) -> 縮放
    love.graphics.push() -- 保存原始狀態 (PUSH 1)
    love.graphics.translate(offsetX, offsetY)

    -- 繪製背景 (現在只需要繪製原始的遊戲大小)
    -- 繪製一個與遊戲區域同樣大小的背景，避免縮放時出現邊緣問題
    love.graphics.setBackgroundColor(MORANDI_COLORS.background)
    love.graphics.setColor(MORANDI_COLORS.background)
    love.graphics.rectangle("fill", 0, 0, GAME_WIDTH, GAME_HEIGHT)
    
    -- ==================================================================
    -- 階段一：繪製所有需要縮放的遊戲世界元素
    -- ==================================================================
    love.graphics.push() -- 保存平移後的狀態，準備縮放 (PUSH 2)
    love.graphics.scale(scale, scale)

    -- 獲取當前網格偏移量。如果正在動畫，則使用動畫 Y 座標；否則為 0
    local gridOffsetY = 0
    if gameState.isAnimating then
        gridOffsetY = gameState.currentGridY or 0 
    end

    love.graphics.setColor(1, 1, 1, 1) -- 重置顏色
    -- 繪製網格中的固定方塊 (作為 Tetris 牆壁 或 Breakout 磚塊)
    for row = 1, GRID_HEIGHT do
        for col = 1, GRID_WIDTH do
            local type = gameState.grid[row][col]
            if type ~= 0 then
                -- 1. 設定實心矩形的顏色
                love.graphics.setColor(MORANDI_COLORS[type] or {1, 1, 1, 1})
                
                -- 2. 繪製實心矩形
                local y = (row - 1) * TILE_SIZE + gridOffsetY
                local x = (col - 1) * TILE_SIZE
                love.graphics.rectangle("fill", x, y, TILE_SIZE, TILE_SIZE)
                
                -- 3. 繪製邊框
                love.graphics.setColor(MORANDI_COLORS.background)
                love.graphics.rectangle("line", x, y, TILE_SIZE, TILE_SIZE)
                
                -- **不需要恢復顏色，因為下一次迴圈會重新設定**
            end
        end
    end

    -- ===================================
    -- 🌟 新增：遊戲區域外框 (邊界)
    -- ===================================
    local GAME_AREA_W = GRID_WIDTH * TILE_SIZE
    local GAME_AREA_H = GRID_HEIGHT * TILE_SIZE
    local BORDER_THICKNESS = 1 -- 邊框厚度，可調整

    -- 選擇一個與莫蘭迪色系協調的淺色或白色邊框
    love.graphics.setColor(1, 1, 1, 1) -- 白色
    love.graphics.setLineWidth(BORDER_THICKNESS)
    
    -- 繪製邊框：使用 "line" 模式，從 (0, 0) 開始
    love.graphics.rectangle(
        "line", 
        0, 
        0, 
        GAME_AREA_W, 
        GAME_AREA_H
    )
    
    -- 重設線條寬度，避免影響其他繪圖（如方塊線條）
    love.graphics.setLineWidth(1)
    
    -- ===================================
    -- TETRIS 模式繪圖
    -- ===================================
    if gameState.mode == "TETRIS" and gameState.currentPiece then
        -- 🌟 新增：繪製預覽方塊 (Ghost Piece)
        if gameState.showGhostPiece then
            local piece = gameState.currentPiece
            local ghostY = calculateGhostPiecePosition(piece)
            
            if piece and ghostY and piece.color then
                -- 設定一個半透明的顏色
                local ghostColor = {piece.color[1], piece.color[2], piece.color[3], 0.3} -- 30% 透明度
                love.graphics.setColor(ghostColor)
                
                if piece.shape then
                    for row = 1, #piece.shape do
                        for col = 1, #piece.shape[row] do
                            if piece.shape[row][col] == 1 then -- 繪製預覽方塊
                                -- 🌟 修正：統一座標計算邏輯，與活動方塊的繪製方式保持一致
                                local x = (piece.x + col - 2) * TILE_SIZE
                                local y = (ghostY + row - 2) * TILE_SIZE + gridOffsetY
                                love.graphics.rectangle("fill", x, y, TILE_SIZE, TILE_SIZE)
                            end
                        end
                    end
                end
            end
        end

        local piece = gameState.currentPiece
        -- 🌟 修正：增加直接的 nil 檢查，確保顏色值有效
        if piece and piece.color then
            love.graphics.setColor(piece.color)
        else
            love.graphics.setColor(1, 1, 1, 1) -- 如果顏色為 nil，預設為白色
        end

        -- 繪製當前下落的方塊
        if piece and piece.shape then
            for row = 1, #piece.shape do
                for col = 1, #piece.shape[row] do
                    if piece.shape[row][col] == 1 then
                        local x = (piece.x + col - 2) * TILE_SIZE
                        -- **🌟 修正：將 gridOffsetY 應用到移動方塊的 Y 座標**
                        -- ✨ 座標系統恢復為 1-based，公式回到熟悉的 -2 ✨
                        local y = (piece.y + row - 2) * TILE_SIZE + gridOffsetY
                        love.graphics.rectangle("fill", x, y, TILE_SIZE, TILE_SIZE)
                        -- 繪製邊框
                        love.graphics.setColor(MORANDI_COLORS.background)
                        love.graphics.rectangle("line", x, y, TILE_SIZE, TILE_SIZE)
                        -- 恢復顏色 (同樣進行 nil 檢查)
                        if piece.color then
                            love.graphics.setColor(piece.color)
                        end
                    end
                end
            end
        end
    
    -- ===================================
    -- BREAKOUT 模式繪圖
    -- ===================================
    elseif gameState.mode == "BREAKOUT" then
        -- 🌟 修正：在繪製板子和球時，應用 gridOffsetY，使其與磚塊同步移動
        -- 繪製板子
        love.graphics.setColor(MORANDI_COLORS.paddle)
        love.graphics.rectangle("fill", gameState.paddle.x, gameState.paddle.y + gridOffsetY, gameState.paddle.w, gameState.paddle.h)
        
        -- 繪製球
        love.graphics.setColor(MORANDI_COLORS.ball)
        love.graphics.circle("fill", gameState.ball.x, gameState.ball.y + gridOffsetY, gameState.ball.r)
    end

    love.graphics.pop() -- 結束縮放，恢復到平移後的狀態 (POP 2)

    -- ==================================================================
    -- 階段二：繪製所有不需要縮放的文字和 UI 疊加層
    -- ==================================================================
    love.graphics.setFont(mainFont)
    love.graphics.setColor(1, 1, 1, 1)

    -- 🌟 修正：根據縮放比例和字體大小，動態計算文字的起始位置和間距
    local scaledInfoX = (GRID_WIDTH * TILE_SIZE) * scale + (10 * scale)
    local lineHeight = mainFont:getHeight() * 1.2 -- 使用字體高度的 1.2 倍作為行高，增加間距
    local currentY = 10 * scale -- 初始 Y 座標也需要縮放

    -- 繪製資訊區 (INFO PANEL)
    -- 模式和切換
    love.graphics.print("MODE: " .. gameState.mode, scaledInfoX, currentY)
    currentY = currentY + lineHeight
    love.graphics.print("(C to switch)", scaledInfoX, currentY)
    currentY = currentY + lineHeight * 1.5 -- 增加一個較大的間隔

    -- 🌟 修正：將分數和等級顯示改為單行，並調整佈局
    -- 分數
    love.graphics.print("SCORE: " .. gameState.score, scaledInfoX, currentY)
    currentY = currentY + lineHeight * 1.5

    -- ===================================
    -- 🌟 新增：下一個方塊預覽
    -- ===================================
    local nextPieceType = gameState.nextPiece
    if nextPieceType and not gameState.isAnimating then
        love.graphics.print("NEXT PIECE:", scaledInfoX, currentY)
        
        local nextPieceShapes = PIECES[nextPieceType]
        local nextShape = nextPieceShapes[1]
        local nextColor = MORANDI_COLORS[nextPieceType]
        
        -- 🌟 智慧佈局：計算方塊實際尺寸並垂直置中
        local minY, maxY = #nextShape + 1, 0
        for r = 1, #nextShape do
            for c = 1, #nextShape[r] do
                if nextShape[r][c] == 1 then
                    minY = math.min(minY, r)
                    maxY = math.max(maxY, r)
                end
            end
        end
        local piecePixelHeight = (maxY - minY + 1) * TILE_SIZE
        
        -- 定義一個固定的預覽框高度（例如 4 格高）
        local previewBoxHeight = 2 * TILE_SIZE -- 🌟 優化：所有預覽方塊最高為 2 格
        -- 計算置中所需的垂直偏移量
        local verticalOffset = (previewBoxHeight - piecePixelHeight) / 2

        -- 定義預覽的繪製起始位置
        local drawStartX = scaledInfoX + (5 * scale)
        local drawStartY = currentY + lineHeight
        
        love.graphics.setColor(nextColor)
        
        for row = 1, #nextShape do
            for col = 1, #nextShape[row] do
                if nextShape[row][col] == 1 then
                    -- 繪製方塊，並應用垂直置中偏移量
                    -- 我們從 `row` 中減去 `minY`，確保是從方塊的頂部開始繪製，而不是從其 4x4 矩陣的頂部
                    local x = drawStartX + ((col - 1) * TILE_SIZE) * scale
                    local y = drawStartY + ((row - minY) * TILE_SIZE) * scale + (verticalOffset * scale)
                    
                    love.graphics.rectangle("fill", x, y, TILE_SIZE * scale, TILE_SIZE * scale)
                    
                    -- 繪製邊框
                    love.graphics.setColor(MORANDI_COLORS.background)
                    love.graphics.rectangle("line", x, y, TILE_SIZE * scale, TILE_SIZE * scale)
                    love.graphics.setColor(nextColor) -- 恢復顏色用於下一個實心方塊
                end
            end
        end
        love.graphics.setColor(1, 1, 1, 1)
    end
    -- ===================================
    -- 🌟 修正：更新 currentY 以繼續佈局
    currentY = currentY + lineHeight + (2 * TILE_SIZE * scale) + (10 * scale)

    -- 等級和行數顯示
    -- 🌟 修正：確保 levelText 變數型別一致，避免警告
    local levelText
    if gameState.level >= 100 then
        levelText = "Max"
    else
        levelText = tostring(gameState.level) -- 將數字轉換為字串
    end
    love.graphics.print("LEVEL: " .. levelText, scaledInfoX, currentY)
    currentY = currentY + lineHeight * 1.5

    -- 控制說明 (需要調整 Y 座標以騰出空間)
    love.graphics.print("CONTROLS:", scaledInfoX, currentY)
    currentY = currentY + lineHeight

    -- 通用控制
    love.graphics.print("Fullscreen: F", scaledInfoX, currentY)
    currentY = currentY + lineHeight
    love.graphics.print("Pause: P", scaledInfoX, currentY)
    currentY = currentY + lineHeight
    
    -- 🌟 新增：音效開關說明
    love.graphics.print("Mute (M): " .. (gameState.soundEnabled and "Off" or "On"), scaledInfoX, currentY)
    currentY = currentY + lineHeight * 1.5

    -- 🌟 模式特定控制 (根據當前模式顯示)
    -- 🌟 修正：調整 Y 座標以避免文字重疊
    if gameState.mode == "TETRIS" then
        love.graphics.print("--- TETRIS ---", scaledInfoX, currentY)
        currentY = currentY + lineHeight
        love.graphics.print("Move: H/L or <-/->", scaledInfoX, currentY)
        currentY = currentY + lineHeight
        love.graphics.print("Rotate: K or UP", scaledInfoX, currentY)
        currentY = currentY + lineHeight
        love.graphics.print("Hard Drop: SPACE", scaledInfoX, currentY)
        currentY = currentY + lineHeight
        love.graphics.print("Ghost Toggle: G", scaledInfoX, currentY)
    elseif gameState.mode == "BREAKOUT" then
        love.graphics.print("--- BREAKOUT ---", scaledInfoX, currentY)
        currentY = currentY + lineHeight
        love.graphics.print("Move: H/L or <-/->", scaledInfoX, currentY)
        currentY = currentY + lineHeight
        love.graphics.print("Slam: SPACE", scaledInfoX, currentY)
    end

    -- ===================================
    -- 🌟 繪製疊加畫面 (TITLE / PAUSED)
    -- ===================================
    -- 🌟 修正：將疊加層的繪製移到縮放區塊內，確保它們能正確放大
    if gameState.state == "TITLE" then
        love.graphics.setColor(0, 0, 0, 0.7) -- 半透明黑色疊加
        love.graphics.rectangle("fill", 0, 0, GAME_WIDTH * scale, GAME_HEIGHT * scale)
        
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf("TETRIS x BREAKOUT", 0, (GAME_HEIGHT / 2 - 40) * scale, GAME_WIDTH * scale, "center")
        love.graphics.printf("PRESS [ENTER] TO START", 0, (GAME_HEIGHT / 2) * scale, GAME_WIDTH * scale, "center")
        
    elseif gameState.state == "PAUSED" then
        love.graphics.setColor(0, 0, 0, 0.5) -- 較淺的半透明黑色疊加
        love.graphics.rectangle("fill", 0, 0, GAME_WIDTH * scale, GAME_HEIGHT * scale)
        
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf("GAME PAUSED", 0, (GAME_HEIGHT / 2 - 20) * scale, GAME_WIDTH * scale, "center")
        love.graphics.printf("PRESS [P] TO RESUME", 0, (GAME_HEIGHT / 2 + 10) * scale, GAME_WIDTH * scale, "center")

    elseif gameState.state == "GAME_OVER" then
        love.graphics.setColor(0, 0, 0, 0.8) -- 更深的半透明黑色疊加
        love.graphics.rectangle("fill", 0, 0, GAME_WIDTH * scale, GAME_HEIGHT * scale)
        
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf("GAME OVER", 0, (GAME_HEIGHT / 2 - 40) * scale, GAME_WIDTH * scale, "center")
        love.graphics.printf("SCORE: " .. gameState.score, 0, (GAME_HEIGHT / 2 - 10) * scale, GAME_WIDTH * scale, "center")
        love.graphics.printf("PRESS [ENTER] TO RESTART", 0, (GAME_HEIGHT / 2 + 20) * scale, GAME_WIDTH * scale, "center")
    end

    -- 恢復到 love.draw 開始前的原始狀態
    love.graphics.pop() -- (POP 1)
end