require "LootBox/LootBoxLoot"
require "LootBox/LootBoxMoveable"

LootBoxServer = LootBoxServer or {}

local MODULE = "LootBox"
local CASH = { "Base.Money", "Base.GoldCoin", "Base.SilverCoin" }
local DEFAULT_SPIN_COST = 10
local MIN_SPIN_COST = 1
local MAX_SPIN_COST = 100
local RARITY_OPTIONS = {
    { name = "Common", option = "CommonChance", default = 30 },
    { name = "Uncommon", option = "UncommonChance", default = 25 },
    { name = "Rare", option = "RareChance", default = 20 },
    { name = "Epic", option = "EpicChance", default = 15 },
    { name = "Contraband", option = "ContrabandChance", default = 10 },
}
local REVEAL_DELAY = 8000

LootBoxServer.pendingByPlayer = LootBoxServer.pendingByPlayer or {}
LootBoxServer.nextRequestId = LootBoxServer.nextRequestId or 0

for _, rarity in ipairs(RARITY_OPTIONS) do
    assert(LootBoxLoot.itemPools[rarity.name], "[LootBox] invalid rarity " .. rarity.name)
end

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

local function result(action, status, rarity, loot, requestId)
    return { action = action, status = status, rarity = rarity, loot = loot, requestId = requestId }
end

local function spinCost(options)
    local cost = tonumber(options and options.SpinCost)
    if not cost or cost ~= math.floor(cost) or cost < MIN_SPIN_COST or cost > MAX_SPIN_COST then
        return DEFAULT_SPIN_COST
    end
    return cost
end

local function findCash(inventory, amount)
    local cash = {}
    for _, fullType in ipairs(CASH) do
        local items = inventory:getAllTypeRecurse(fullType)
        for index = 0, items:size() - 1 do
            table.insert(cash, items:get(index))
            if #cash == amount then return cash end
        end
    end
    return nil
end

local function isGatchaMachine(object)
    return LootBoxMoveable.isMachineObject(object)
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

function LootBoxServer.handleOpen(player, args)
    if not enabled() then return result("open", "disabled") end

    local _, errorStatus = machineNear(player, args or {})
    if errorStatus then
        return result("open", errorStatus)
    end

    local playerKey = tostring(player:getUsername())
    local pending = LootBoxServer.pendingByPlayer[playerKey]
    if pending then
        return result("open", "ok", pending.rarity, pending.loot, pending.requestId)
    end

    local inventory = player:getInventory()
    local options = settings()
    local freeOrder = options and options.FreeOrders == true
    local cost = spinCost(options)
    local cash = not freeOrder and findCash(inventory, cost) or nil
    if not freeOrder and not cash then
        return result("open", "no_money")
    end

    local rarities, totalWeight = configuredRarities(settings())
    local rarity = LootBoxLoot.selectRarity(ZombRand(totalWeight) + 1, rarities)
    local rewards, loot = prepareReward(LootBoxLoot.randomItem(rarity))
    if not rewards then
        return result("open", "config_error")
    end

    if cash then
        for _, cashItem in ipairs(cash) do
            local cashContainer = cashItem:getContainer()
            cashContainer:Remove(cashItem)
            sendRemoveItemFromContainer(cashContainer, cashItem)
        end
    end

    LootBoxServer.nextRequestId = LootBoxServer.nextRequestId + 1
    local requestId = playerKey .. ":" .. tostring(getTimestampMs())
        .. ":" .. tostring(LootBoxServer.nextRequestId)
    LootBoxServer.pendingByPlayer[playerKey] = {
        requestId = requestId,
        rarity = rarity,
        rewards = rewards,
        loot = loot,
        readyAt = getTimestampMs() + REVEAL_DELAY,
    }
    debugLog("open player=" .. playerKey .. " free=" .. tostring(freeOrder)
        .. " cost=" .. tostring(freeOrder and 0 or cost)
        .. " rarity=" .. rarity .. " loot=" .. loot)
    return result("open", "ok", rarity, loot, requestId)
end

function LootBoxServer.handleClaim(player, args)
    local requestId = args and tostring(args.requestId or "")
    local playerKey = tostring(player:getUsername())
    local pending = LootBoxServer.pendingByPlayer[playerKey]
    if not pending or pending.requestId ~= requestId then
        return result("claim", "invalid_request")
    end
    if getTimestampMs() < pending.readyAt then
        return result("claim", "pending")
    end

    local inventory = player:getInventory()
    LootBoxServer.pendingByPlayer[playerKey] = nil
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
        response = LootBoxServer.handleOpen(player, args)
    elseif command == "claim" then
        response = LootBoxServer.handleClaim(player, args)
    end
    if response then
        sendServerCommand(player, MODULE, "result", response)
    end
end

Events.OnClientCommand.Add(onClientCommand)
