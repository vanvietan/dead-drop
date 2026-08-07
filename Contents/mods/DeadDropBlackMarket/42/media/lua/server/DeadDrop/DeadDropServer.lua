require "DeadDrop/DeadDropLoot"
require "DeadDrop/DeadDropMoveable"

DeadDropServer = DeadDropServer or {}

local MODULE = "DeadDrop"
local CASH = { "Base.Money", "Base.GoldCoin", "Base.SilverCoin" }
local RARITY_OPTIONS = {
    { name = "Common", option = "CommonChance", default = 30 },
    { name = "Uncommon", option = "UncommonChance", default = 25 },
    { name = "Rare", option = "RareChance", default = 20 },
    { name = "Epic", option = "EpicChance", default = 15 },
    { name = "Contraband", option = "ContrabandChance", default = 10 },
}
local REVEAL_DELAY = 8000

DeadDropServer.pendingByPlayer = DeadDropServer.pendingByPlayer or {}
DeadDropServer.nextRequestId = DeadDropServer.nextRequestId or 0

for _, rarity in ipairs(RARITY_OPTIONS) do
    assert(DeadDropLoot.itemPools[rarity.name], "[DeadDrop] invalid rarity " .. rarity.name)
end

local function settings()
    return SandboxVars and SandboxVars.DeadDrop or nil
end

local function enabled()
    local options = settings()
    return not options or options.Enabled ~= false
end

local function debugLog(message)
    local options = settings()
    if options and options.DebugLogging then print("[DeadDrop] " .. message) end
end

local function result(action, status, rarity, loot, requestId)
    return { action = action, status = status, rarity = rarity, loot = loot, requestId = requestId }
end

local function findFirstItem(inventory, fullTypes)
    for _, fullType in ipairs(fullTypes) do
        local items = inventory:getAllTypeRecurse(fullType)
        if not items:isEmpty() then
            return items:get(0)
        end
    end
end

local function isGatchaMachine(object)
    return DeadDropMoveable.isMachineObject(object)
end

local function isInteger(value)
    return value and value == math.floor(value)
end

local function machineNear(player, args)
    local x, y, z, index = tonumber(args.x), tonumber(args.y), tonumber(args.z), tonumber(args.objectIndex)
    if not isInteger(x) or not isInteger(y) or not isInteger(z)
            or not isInteger(index) or index < 0 then
        return nil, "invalid_machine"
    end

    local square = getCell():getGridSquare(x, y, z)
    if not square or index >= square:getObjects():size() then
        return nil, "invalid_machine"
    end

    local machine = square:getObjects():get(index)
    if not isGatchaMachine(machine) then
        return nil, "invalid_machine"
    end
    if player:getZ() ~= z or player:DistToSquared(x + 0.5, y + 0.5) > 4 then
        return nil, "too_far"
    end
    return machine
end

local function prepareReward(entry)
    local rewards = {}
    if not entry or not entry.fullType or type(entry.quantity) ~= "number"
            or entry.quantity < 1 or entry.quantity ~= math.floor(entry.quantity)
            or not ScriptManager.instance:FindItem(entry.fullType) then
        return nil
    end
    for _ = 1, entry.quantity do
        local item = instanceItem(entry.fullType)
        if not item then return nil end
        table.insert(rewards, item)
    end
    return rewards, entry.fullType .. ":" .. entry.quantity
end

local function configuredRarities(options)
    local rarities = {}
    local total = 0
    for _, config in ipairs(RARITY_OPTIONS) do
        local weight = tonumber(options and options[config.option])
        if weight == nil then weight = config.default end
        weight = math.max(0, math.min(100, math.floor(weight)))
        table.insert(rarities, { name = config.name, weight = weight })
        total = total + weight
    end

    -- An all-zero setup cannot be rolled; restore the documented defaults.
    if total == 0 then
        rarities = {}
        for _, config in ipairs(RARITY_OPTIONS) do
            table.insert(rarities, { name = config.name, weight = config.default })
        end
        total = 100
    end
    return rarities, total
end

function DeadDropServer.handleOpen(player, args)
    if not enabled() then return result("open", "disabled") end

    local _, errorStatus = machineNear(player, args or {})
    if errorStatus then
        return result("open", errorStatus)
    end

    local playerKey = tostring(player:getUsername())
    local pending = DeadDropServer.pendingByPlayer[playerKey]
    if pending then
        return result("open", "ok", pending.rarity, pending.loot, pending.requestId)
    end

    local inventory = player:getInventory()
    local options = settings()
    local freeOrder = options and options.FreeOrders == true
    local cash = not freeOrder and findFirstItem(inventory, CASH) or nil
    if not freeOrder and not cash then
        return result("open", "no_money")
    end

    local rarities, totalWeight = configuredRarities(settings())
    local rarity = DeadDropLoot.selectRarity(ZombRand(totalWeight) + 1, rarities)
    local rewards, loot = prepareReward(DeadDropLoot.randomItem(rarity))
    if not rewards then
        return result("open", "config_error")
    end

    if cash then
        local cashContainer = cash:getContainer()
        cashContainer:Remove(cash)
        sendRemoveItemFromContainer(cashContainer, cash)
    end

    DeadDropServer.nextRequestId = DeadDropServer.nextRequestId + 1
    local requestId = playerKey .. ":" .. tostring(getTimestampMs())
        .. ":" .. tostring(DeadDropServer.nextRequestId)
    DeadDropServer.pendingByPlayer[playerKey] = {
        requestId = requestId,
        rarity = rarity,
        rewards = rewards,
        loot = loot,
        readyAt = getTimestampMs() + REVEAL_DELAY,
    }
    debugLog("open player=" .. playerKey .. " free=" .. tostring(freeOrder)
        .. " rarity=" .. rarity .. " loot=" .. loot)
    return result("open", "ok", rarity, loot, requestId)
end

function DeadDropServer.handleClaim(player, args)
    local requestId = args and tostring(args.requestId or "")
    local playerKey = tostring(player:getUsername())
    local pending = DeadDropServer.pendingByPlayer[playerKey]
    if not pending or pending.requestId ~= requestId then
        return result("claim", "invalid_request")
    end
    if getTimestampMs() < pending.readyAt then
        return result("claim", "pending")
    end

    local inventory = player:getInventory()
    DeadDropServer.pendingByPlayer[playerKey] = nil
    for _, item in ipairs(pending.rewards) do
        inventory:AddItem(item)
        sendAddItemToContainer(inventory, item)
    end
    debugLog("claim player=" .. playerKey .. " rarity=" .. pending.rarity .. " loot=" .. pending.loot)
    return result("claim", "ok", pending.rarity, pending.loot)
end

local function onClientCommand(module, command, player, args)
    if module ~= MODULE then return end

    local response
    if command == "open" then
        response = DeadDropServer.handleOpen(player, args)
    elseif command == "claim" then
        response = DeadDropServer.handleClaim(player, args)
    end
    if response then
        sendServerCommand(player, MODULE, "result", response)
    end
end

Events.OnClientCommand.Add(onClientCommand)
