-- src/components/Piece.lua
local constants = require("src.constants")
local utils = require("src.utils")
local Piece = {}
Piece.__index = Piece

function Piece.new(pieceType)
    local self = setmetatable({}, Piece)
    self.type = pieceType or "I"
    local shapes = constants.PIECES[self.type]
    self.shape = shapes[1]
    self.color = constants.MORANDI_COLORS[self.type] or {1, 1, 1, 1}
    
    self.x = math.floor((constants.GRID_WIDTH - #self.shape[1]) / 2) + 1
    self.y = 0 -- 1-based, 0 代表網格上方
    
    return self
end

function Piece:rotate(grid)
    local newShape = utils.rotate(self.shape)
    -- 牆踢 (Wall Kick) 簡化實作
    if not utils.checkCollision(self.x, self.y, newShape, grid.data, grid.width, grid.height) then
        self.shape = newShape
        return true
    elseif not utils.checkCollision(self.x + 1, self.y, newShape, grid.data, grid.width, grid.height) then
        self.x = self.x + 1
        self.shape = newShape
        return true
    elseif not utils.checkCollision(self.x - 1, self.y, newShape, grid.data, grid.width, grid.height) then
        self.x = self.x - 1
        self.shape = newShape
        return true
    end
    return false
end

function Piece:move(dx, dy, grid)
    if not utils.checkCollision(self.x + dx, self.y + dy, self.shape, grid.data, grid.width, grid.height) then
        self.x = self.x + dx
        self.y = self.y + dy
        return true
    end
    return false
end

function Piece:calculateGhostY(grid)
    return utils.calculateGhostPiecePosition(self, grid.data, grid.width, grid.height)
end

function Piece:draw(gridOffsetY, showGhost, grid)
    if showGhost then
        local ghostY = self:calculateGhostY(grid)
        if ghostY then
            local ghostColor = {self.color[1], self.color[2], self.color[3], 0.3}
            love.graphics.setColor(ghostColor)
            self:_drawShape(self.x, ghostY, gridOffsetY)
        end
    end
    
    love.graphics.setColor(self.color)
    self:_drawShape(self.x, self.y, gridOffsetY)
end

function Piece:_drawShape(x, y, gridOffsetY)
    for row = 1, #self.shape do
        for col = 1, #self.shape[row] do
            if self.shape[row][col] == 1 then
                local drawX = (x + col - 2) * constants.TILE_SIZE
                local drawY = (y + row - 2) * constants.TILE_SIZE + (gridOffsetY or 0)
                love.graphics.rectangle("fill", drawX, drawY, constants.TILE_SIZE, constants.TILE_SIZE)
                
                -- 邊框
                local oldColor = {love.graphics.getColor()}
                love.graphics.setColor(constants.MORANDI_COLORS.background)
                love.graphics.rectangle("line", drawX, drawY, constants.TILE_SIZE, constants.TILE_SIZE)
                love.graphics.setColor(oldColor)
            end
        end
    end
end

return Piece
