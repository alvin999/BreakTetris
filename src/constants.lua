-- src/constants.lua
local constants = {}

-- 網格與視窗配置
constants.GRID_WIDTH = 10
constants.GRID_HEIGHT = 20
constants.TILE_SIZE = 20
constants.INFO_WIDTH = 150
constants.GAME_WIDTH = constants.GRID_WIDTH * constants.TILE_SIZE + constants.INFO_WIDTH
constants.GAME_HEIGHT = constants.GRID_HEIGHT * constants.TILE_SIZE

-- 物理參數
constants.SLAM_OFFSET = 5
constants.SLAM_WINDOW_DURATION = 0.2
constants.BALL_MAX_SPEED = 1000

-- 莫蘭迪色系
constants.MORANDI_COLORS = {
    background = {40/255, 46/255, 50/255, 1},
    I = {149/255, 172/255, 173/255, 1},
    O = {173/255, 151/255, 126/255, 1},
    T = {136/255, 142/255, 151/255, 1},
    L = {181/255, 169/255, 147/255, 1},
    J = {141/255, 164/255, 155/255, 1},
    S = {167/255, 173/255, 175/255, 1},
    Z = {156/255, 146/255, 155/255, 1},
    paddle = {210/255, 210/255, 210/255, 1},
    ball = {230/255, 150/255, 150/255, 1},
}

-- 俄羅斯方塊定義
constants.PIECES = {
    I = { { {0,0,0,0}, {1,1,1,1}, {0,0,0,0}, {0,0,0,0} } },
    O = { { {1,1}, {1,1} } },
    T = { { {0,1,0}, {1,1,1}, {0,0,0} } },
    L = { { {0,0,1}, {1,1,1}, {0,0,0} } },
    J = { { {1,0,0}, {1,1,1}, {0,0,0} } },
    S = { { {0,1,1}, {1,1,0}, {0,0,0} } },
    Z = { { {1,1,0}, {0,1,1}, {0,0,0} } }
}

-- 延遲與計時
constants.LOCK_DELAY = 0.5
constants.MOVE_DELAY = 0.15
constants.MOVE_INTERVAL = 0.05
constants.ANIMATION_DURATION = 0.5

return constants
