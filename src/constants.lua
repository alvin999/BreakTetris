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

-- 道具系統參數
constants.POWERUP_DROP_CHANCE = 0.30 -- 30% 掉落機率，讓遊戲節奏更豐富暢快
constants.POWERUP_FALL_SPEED = 85    -- 道具緩降速度
constants.POWERUP_WIDTH = 22         -- 道具膠囊寬度
constants.POWERUP_HEIGHT = 14        -- 道具膠囊高度 (提升容納文字空間)
constants.PADDLE_BASE_WIDTH = 80     -- 板子基礎寬度
constants.PADDLE_EXPAND_STEP = 30    -- 每次加長累加 30px
constants.PADDLE_MAX_WIDTH = constants.GRID_WIDTH * constants.TILE_SIZE -- 滿版寬度 (200px)

-- 道具種類定義與莫蘭迪專屬色彩
constants.POWERUP_TYPES = {
    LONG = {
        id = "LONG",
        code = "L",
        name = "Long Paddle",
        label = "加長板子",
        duration = 15,
        color = {142/255, 194/255, 163/255, 1} -- 莫蘭迪鼠尾草綠
    },
    MULTI = {
        id = "MULTI",
        code = "M",
        name = "Multi Ball",
        label = "多球分裂",
        duration = 0,
        color = {235/255, 178/255, 130/255, 1} -- 莫蘭迪暖杏橘
    },
    PIERCE = {
        id = "PIERCE",
        code = "P",
        name = "Pierce Ball",
        label = "穿透破壞",
        duration = 8,
        color = {222/255, 142/255, 156/255, 1} -- 莫蘭迪玫瑰粉
    },
    SAFETY = {
        id = "SAFETY",
        code = "S",
        name = "Safety Net",
        label = "安全護網",
        duration = 0,
        color = {136/255, 186/255, 218/255, 1} -- 莫蘭迪天青藍
    },
    COLOR_BOMB = {
        id = "COLOR_BOMB",
        code = "C",
        name = "Color Bomb",
        label = "同色爆破",
        duration = 10,
        color = {192/255, 152/255, 202/255, 1} -- 莫蘭迪丁香紫
    },
    LASER = {
        id = "LASER",
        code = "A",
        name = "Laser Gun",
        label = "雷射火砲",
        duration = 12,
        color = {238/255, 208/255, 126/255, 1} -- 莫蘭迪琥珀金
    }
}

return constants
