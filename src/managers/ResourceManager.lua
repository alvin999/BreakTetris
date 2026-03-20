-- src/managers/ResourceManager.lua
local constants = require("src.constants")
local ResourceManager = {}
ResourceManager.sounds = {}
ResourceManager.font = nil
ResourceManager.soundEnabled = true

function ResourceManager.load()
    -- 載入音效
    local soundFiles = {
        lock = "sounds/lock.mp3",
        start = "sounds/start.mp3",
        endgame = "sounds/endgame.mp3",
        clear = "sounds/clear.mp3",
        blip = "sounds/blip.mp3"
    }
    
    for name, path in pairs(soundFiles) do
        local ok, source = pcall(love.audio.newSource, path, "static")
        if ok then
            ResourceManager.sounds[name] = source
        else
            print("Warning: Could not load sound " .. name .. " from " .. path)
        end
    end
    
    -- 載入預設字體
    ResourceManager.updateFont(1) -- 預設縮放為 1
end

function ResourceManager.playSound(name)
    if ResourceManager.soundEnabled and ResourceManager.sounds[name] then
        ResourceManager.sounds[name]:stop()
        ResourceManager.sounds[name]:play()
    end
end

function ResourceManager.updateFont(scale)
    local fontSize = math.ceil(12 * scale)
    if fontSize > 0 then
        ResourceManager.font = love.graphics.newFont(fontSize, "none")
        ResourceManager.font:setFilter("linear", "linear")
    end
end

return ResourceManager
