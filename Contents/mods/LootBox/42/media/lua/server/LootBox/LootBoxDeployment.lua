if isClient() then return end

require "LootBox/LootBoxMoveable"

LootBoxDeployment = LootBoxDeployment or {}

local DATA_KEY = "LootBoxDeployment"
local SPAWN_CHANCE = 100
local ELIGIBLE_ROOMS = {
    conveniencestore = true,
    gasstore = true,
    gas2go = true,
    fossoil = true,
    thundergas = true,
}

local function settings()
    return SandboxVars and SandboxVars.LootBox or nil
end

local function enabled()
    local options = settings()
    return not options or options.Enabled ~= false
end

local function debugLog(message)
    local options = settings()
    if options and options.DebugLogging then print("[LootBox] " .. message) end
end

local function deploymentData()
    return ModData.getOrCreate(DATA_KEY)
end

local function roomName(square)
    local room = square and square:getRoom()
    local name = room and room:getName()
    return name and string.lower(tostring(name)) or nil
end

local function buildingKey(building)
    local def = building and building:getDef()
    if not def then return nil end
    return table.concat({
        tostring(def:getX()), tostring(def:getY()),
        tostring(def:getW()), tostring(def:getH()),
    }, ":")
end

local function hasLoadedMachine(building)
    local def = building and building:getDef()
    if not def then return false end

    local zLevels = {}
    local rooms = def:getRooms()
    for index = 0, rooms:size() - 1 do
        zLevels[rooms:get(index):getZ()] = true
    end

    local cell = getCell()
    for z in pairs(zLevels) do
        for x = def:getX(), def:getX2() do
            for y = def:getY(), def:getY2() do
                local candidate = cell:getGridSquare(x, y, z)
                if candidate and candidate:getBuilding() == building then
                    local objects = candidate:getObjects()
                    for index = 0, objects:size() - 1 do
                        if LootBoxMoveable.isMachineObject(objects:get(index)) then
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

local function wallFacing(square)
    -- Walls are stored on the north/west edge of a square. East/south walls
    -- therefore belong to the neighbouring square. Face the machine into the
    -- room, away from whichever wall it is placed against.
    if square:getWall(true) then return "S" end
    if square:getWall(false) then return "E" end

    local east = square:getE()
    if east and east:getWall(false) then return "W" end

    local south = square:getS()
    if south and south:getWall(true) then return "N" end
    return nil
end

local function placementFacing(square)
    if not square:getFloor() or square:isVehicleIntersecting() or not square:isFree(true) then
        return nil
    end
    return wallFacing(square)
end

local function placeMachine(square, facing, key)
    local spriteName = LootBoxMoveable.spriteForFacing(facing)
    if not spriteName then return false end

    local object = IsoObject.new(square, spriteName, LootBoxMoveable.machineName())
    if not object then return false end

    square:AddTileObject(object)
    LootBoxMoveable.markMachineObject(object)
    square:RecalcAllWithNeighbours(true)
    if isServer() then object:transmitCompleteItemToClients() end

    deploymentData()[key] = "placed"
    debugLog("deployed building=" .. key .. " x=" .. square:getX()
        .. " y=" .. square:getY() .. " z=" .. square:getZ()
        .. " facing=" .. facing)
    return true
end

local function onLoadGridSquare(square)
    if not enabled() or not square or not ELIGIBLE_ROOMS[roomName(square)] then return end

    local building = square:getBuilding()
    local key = buildingKey(building)
    if not key then return end

    local data = deploymentData()
    local state = data[key]
    if state == "skipped" or state == "placed" then return end

    -- Existing saves may already contain a placed machine in an eligible
    -- store. Claim the building before making a new roll so it never receives
    -- a duplicate.
    if hasLoadedMachine(building) then
        data[key] = "placed"
        return
    end

    if not state then
        state = ZombRand(100) < SPAWN_CHANCE and "pending" or "skipped"
        data[key] = state
        debugLog("deployment roll building=" .. key .. " state=" .. state)
    end
    if state ~= "pending" then return end

    local facing = placementFacing(square)
    if facing then placeMachine(square, facing, key) end
end

Events.LoadGridsquare.Add(onLoadGridSquare)
