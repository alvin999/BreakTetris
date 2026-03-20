-- src/states/StateManager.lua
local StateManager = {}
StateManager.states = {}
StateManager.current = nil

function StateManager.register(name, state)
    StateManager.states[name] = state
end

function StateManager.switch(name, params)
    if StateManager.current and StateManager.current.exit then
        StateManager.current:exit()
    end
    
    StateManager.current = StateManager.states[name]
    
    if StateManager.current and StateManager.current.enter then
        StateManager.current:enter(params)
    end
end

function StateManager.update(dt)
    if StateManager.current and StateManager.current.update then
        StateManager.current:update(dt)
    end
end

function StateManager.draw()
    if StateManager.current and StateManager.current.draw then
        StateManager.current:draw()
    end
end

function StateManager.drawUI(scale)
    if StateManager.current and StateManager.current.drawUI then
        StateManager.current:drawUI(scale)
    end
end

function StateManager.keypressed(key, scancode)
    if StateManager.current and StateManager.current.keypressed then
        StateManager.current:keypressed(key, scancode)
    end
end

function StateManager.keyreleased(key, scancode)
    if StateManager.current and StateManager.current.keyreleased then
        StateManager.current:keyreleased(key, scancode)
    end
end

return StateManager
