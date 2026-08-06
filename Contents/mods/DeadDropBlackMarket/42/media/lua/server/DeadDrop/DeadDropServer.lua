require "DeadDrop/DeadDropLoot"

DeadDropServer = DeadDropServer or {}

local MODULE = "DeadDrop"
local CRATE = "DeadDrop.BlackMarketCrate"
local CASH = { "Base.Money", "Base.GoldCoin", "Base.SilverCoin" }
local FORCED_RARITY = { [2] = "Common", [3] = "Uncommon", [4] = "Rare", [5] = "Contraband" }

for _, rarity in pairs(FORCED_RARITY) do
    assert(DeadDropLoot.bundles[rarity], "[DeadDrop] invalid forced rarity " .. rarity)
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

local function result(action, status, rarity, loot)
    return { action = action, status = status, rarity = rarity, loot = loot }
end

local function findFirstItem(inventory, fullTypes)
    for _, fullType in ipairs(fullTypes) do
        local items = inventory:getAllTypeRecurse(fullType)
        if not items:isEmpty() then
            return items:get(0)
        end
    end
end

local function findItemById(inventory, fullType, itemId)
    local items = inventory:getAllTypeRecurse(fullType)
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item:getID() == itemId then
            return item
        end
    end
end

local function activeRadioNear(player, args)
    local x, y, z, index = tonumber(args.x), tonumber(args.y), tonumber(args.z), tonumber(args.objectIndex)
    if not x or not y or not z or not index or index < 0 then
        return nil, "invalid_radio"
    end

    local square = getCell():getGridSquare(x, y, z)
    if not square or index >= square:getObjects():size() then
        return nil, "invalid_radio"
    end

    local radio = square:getObjects():get(index)
    local device = instanceof(radio, "IsoWaveSignal") and radio:getDeviceData() or nil
    if not device or device:getIsTelevision() then
        return nil, "invalid_radio"
    end
    if player:getZ() ~= z or player:DistToSquared(x + 0.5, y + 0.5) > 4 then
        return nil, "too_far"
    end
    if not device:getIsTurnedOn() or device:getPower() <= 0 then
        return nil, "radio_off"
    end
    return radio
end

function DeadDropServer.handleOrder(player, args)
    if not enabled() then return result("order", "disabled") end

    local _, errorStatus = activeRadioNear(player, args or {})
    if errorStatus then
        return result("order", errorStatus)
    end

    local inventory = player:getInventory()
    local options = settings()
    local freeOrder = options and options.FreeOrders == true
    local cash = not freeOrder and findFirstItem(inventory, CASH) or nil
    if not freeOrder and not cash then
        return result("order", "no_money")
    end

    local crate = instanceItem(CRATE)
    if not crate then
        return result("order", "config_error")
    end

    if cash then
        local cashContainer = cash:getContainer()
        cashContainer:Remove(cash)
        sendRemoveItemFromContainer(cashContainer, cash)
    end
    inventory:AddItem(crate)
    sendAddItemToContainer(inventory, crate)
    debugLog("order player=" .. tostring(player:getUsername()) .. " free=" .. tostring(freeOrder))
    return result("order", "ok")
end

local function prepareRewards(bundle)
    local rewards = {}
    local loot = {}
    if not bundle then return nil end

    for _, entry in ipairs(bundle) do
        if not entry.fullType or type(entry.quantity) ~= "number" or entry.quantity < 1
                or entry.quantity ~= math.floor(entry.quantity)
                or not ScriptManager.instance:FindItem(entry.fullType) then
            return nil
        end
        for _ = 1, entry.quantity do
            local item = instanceItem(entry.fullType)
            if not item then return nil end
            table.insert(rewards, item)
        end
        table.insert(loot, entry.fullType .. ":" .. entry.quantity)
    end
    return rewards, table.concat(loot, "|")
end

function DeadDropServer.handleOpen(player, args)
    if not enabled() then return result("open", "disabled") end

    local itemId = args and tonumber(args.itemId)
    if not itemId then
        return result("open", "crate_missing")
    end

    local inventory = player:getInventory()
    local crate = findItemById(inventory, CRATE, itemId)
    if not crate then
        return result("open", "crate_missing")
    end

    local options = settings()
    local rarity = FORCED_RARITY[options and options.ForcedRarity or 1]
        or DeadDropLoot.selectRarity(ZombRand(100) + 1)
    local rewards, loot = prepareRewards(DeadDropLoot.randomBundle(rarity))
    if not rewards then
        return result("open", "config_error")
    end

    local crateContainer = crate:getContainer()
    crateContainer:Remove(crate)
    sendRemoveItemFromContainer(crateContainer, crate)
    for _, item in ipairs(rewards) do
        inventory:AddItem(item)
        sendAddItemToContainer(inventory, item)
    end
    debugLog("open player=" .. tostring(player:getUsername()) .. " rarity=" .. rarity .. " loot=" .. loot)
    return result("open", "ok", rarity, loot)
end

local function onClientCommand(module, command, player, args)
    if module ~= MODULE then return end

    local response
    if command == "order" then
        response = DeadDropServer.handleOrder(player, args)
    elseif command == "open" then
        response = DeadDropServer.handleOpen(player, args)
    end
    if response then
        sendServerCommand(player, MODULE, "result", response)
    end
end

Events.OnClientCommand.Add(onClientCommand)
