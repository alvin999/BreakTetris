-- src/states/BaseState.lua
local BaseState = {}
BaseState.__index = BaseState

function BaseState.new()
    return setmetatable({}, BaseState)
end

function BaseState:enter(params) end
function BaseState:exit() end
function BaseState:update(dt) end
function BaseState:draw() end
function BaseState:drawUI() end
function BaseState:keypressed(key) end
function BaseState:keyreleased(key) end

return BaseState
