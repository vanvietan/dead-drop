require "ISUI/ISWorldObjectContextMenu"
require "ISUI/ISToolTip"
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "DeadDrop/DeadDropLoot"

DeadDropClient = DeadDropClient or {}

local MODULE = "DeadDrop"
local CRATE = "DeadDrop.BlackMarketCrate"
local CASH = { "Base.Money", "Base.GoldCoin", "Base.SilverCoin" }
local REEL_DURATION = 4000
local LOCK_DURATION = 1000
local REVEAL_TIME = REEL_DURATION + LOCK_DURATION
local REEL_ITEM_COUNT = 32

local messages = {
    no_money = "You need $1 in cash.",
    radio_off = "The radio must be turned on and powered.",
    invalid_radio = "That radio is no longer available.",
    too_far = "Move closer to the radio.",
    crate_missing = "That crate is no longer in your inventory.",
    config_error = "Dead Drop loot configuration is invalid.",
    disabled = "Dead Drop is disabled in Sandbox Options.",
    pending = "Finish opening the current crate first.",
}

local rarityColors = {
    Common = { r = 0.62, g = 0.62, b = 0.55 },
    Uncommon = { r = 0.36, g = 0.62, b = 0.38 },
    Rare = { r = 0.30, g = 0.50, b = 0.76 },
    Contraband = { r = 0.70, g = 0.18, b = 0.18 },
}

local scanningColor = { r = 0.58, g = 0.57, b = 0.52 }

DeadDropOpenPanel = ISPanel:derive("DeadDropOpenPanel")

function DeadDropOpenPanel:new(rarity, lootText, itemId)
    local width, height = 460, 330
    local panel = ISPanel:new((getCore():getScreenWidth() - width) / 2,
        (getCore():getScreenHeight() - height) / 2, width, height)
    setmetatable(panel, self)
    self.__index = self
    panel.rarity = rarity or "Common"
    panel.itemId = itemId
    panel.color = rarityColors[panel.rarity] or rarityColors.Common
    panel.loot = {}
    for token in string.gmatch(lootText or "", "[^|]+") do
        local fullType, quantity = string.match(token, "^([^:]+):(%d+)$")
        local scriptItem = fullType and ScriptManager.instance:FindItem(fullType) or nil
        if scriptItem then
            table.insert(panel.loot, {
                name = scriptItem:getDisplayName(),
                quantity = tonumber(quantity),
                texture = scriptItem:getNormalTexture(),
            })
        end
    end
    panel.reel = {}
    local candidates = {}
    for _, bundles in pairs(DeadDropLoot.bundles) do
        for _, bundle in ipairs(bundles) do
            for _, entry in ipairs(bundle) do
                local scriptItem = ScriptManager.instance:FindItem(entry.fullType)
                if scriptItem then table.insert(candidates, scriptItem:getNormalTexture()) end
            end
        end
    end
    for _ = 1, REEL_ITEM_COUNT do
        table.insert(panel.reel, candidates[ZombRand(#candidates) + 1])
    end
    table.insert(panel.reel, panel.loot[1] and panel.loot[1].texture or nil)
    panel.startedAt = getTimestampMs()
    panel.revealed = false
    panel.backgroundColor = { r = 0.055, g = 0.06, b = 0.055, a = 0.94 }
    panel.borderColor = { r = 0.40, g = 0.39, b = 0.34, a = 1 }
    panel:setWantKeyEvents(true)
    return panel
end

function DeadDropOpenPanel:initialise()
    ISPanel.initialise(self)
    self.closeButton = ISButton:new(self.width / 2 - 55, self.height - 42, 110, 28,
        "CLOSE", self, DeadDropOpenPanel.destroy)
    self.closeButton:initialise()
    self.closeButton:instantiate()
    self.closeButton:setVisible(false)
    self:addChild(self.closeButton)
end

function DeadDropOpenPanel:update()
    ISPanel.update(self)
    self:setX((getCore():getScreenWidth() - self.width) / 2)
    self:setY((getCore():getScreenHeight() - self.height) / 2)
    if not self.claimSent and getTimestampMs() - self.startedAt >= REVEAL_TIME then
        self.claimSent = true
        DeadDropClient.claim(self.itemId)
    end
end

function DeadDropOpenPanel:reveal()
    self.revealed = true
    self.closeButton:setVisible(true)
end

function DeadDropOpenPanel:prerender()
    ISPanel.prerender(self)
    local elapsed = getTimestampMs() - self.startedAt
    -- Do not expose the result through the accent color before the reveal.
    local color = self.revealed and self.color or scanningColor
    local title = elapsed < REEL_DURATION and "SCANNING SUPPLY CHANNEL..."
        or (not self.revealed and "SIGNAL LOCKED" or string.upper(self.rarity) .. " CACHE")

    self:drawRect(16, 16, self.width - 32, 3, 0.9, color.r, color.g, color.b)
    self:drawTextCentre(title, self.width / 2, 30, 0.86, 0.85, 0.77, 1, UIFont.Medium)

    if not self.revealed then
        local reelLeft, reelRight, slotWidth = 30, self.width - 30, 88
        local progress = math.min(elapsed / REEL_DURATION, 1)
        local eased = 1 - math.pow(1 - progress, 3)
        local target = reelLeft + (#self.reel - 1) * slotWidth - self.width / 2
        local offset = target * eased

        local reelTop, reelHeight = 68, 92
        self:drawRect(reelLeft, reelTop, reelRight - reelLeft, reelHeight,
            0.72, 0.025, 0.027, 0.025)

        -- Keep partially-visible slots inside the reel viewport. The extra
        -- 44px in the visibility check makes slots enter smoothly, but without
        -- a stencil their backgrounds and icons spill over the panel edges.
        self:setStencilRect(reelLeft, reelTop, reelRight - reelLeft, reelHeight)
        for index, texture in ipairs(self.reel) do
            local x = reelLeft + (index - 1) * slotWidth - offset
            if x > reelLeft - 44 and x < reelRight + 44 then
                self:drawRect(x - 36, 74, 72, 80, 0.84, 0.10, 0.105, 0.095)
                if texture then
                    self:drawTextureScaledAspect(texture, x - 25, 87, 50, 50, 1, 1, 1, 1)
                end
            end
        end
        self:clearStencilRect()
        self:drawRect(self.width / 2 - 38, 68, 76, 3, 1, color.r, color.g, color.b)
        self:drawRect(self.width / 2 - 38, 157, 76, 3, 1, color.r, color.g, color.b)
        local status = elapsed < REEL_DURATION and "SIGNAL LOCK " .. math.floor(progress * 100) .. "%"
            or "TARGET ACQUIRED"
        self:drawTextCentre(status, self.width / 2, 176,
            0.55, 0.55, 0.50, 1, UIFont.Small)
    elseif self.revealed then
        self:drawTextCentre("CONTENTS", self.width / 2, 88, color.r, color.g, color.b, 1, UIFont.Small)
        for index, item in ipairs(self.loot) do
            if item.texture then
                self:drawTextureScaledAspect(item.texture, 116, 112 + (index - 1) * 48, 36, 36, 1, 1, 1, 1)
            end
            self:drawText(item.name .. " x" .. item.quantity, 166, 121 + (index - 1) * 48,
                0.78, 0.77, 0.69, 1, UIFont.Small)
        end
    end
end

function DeadDropOpenPanel:onKeyPress(key)
    if self.revealed and key == Keyboard.KEY_ESCAPE then self:destroy() end
end

function DeadDropOpenPanel:destroy()
    self:removeFromUIManager()
    if DeadDropClient.openPanel == self then DeadDropClient.openPanel = nil end
end

function DeadDropOpenPanel.show(rarity, loot, itemId)
    if DeadDropClient.openPanel then DeadDropClient.openPanel:destroy() end
    local panel = DeadDropOpenPanel:new(rarity, loot, itemId)
    panel:initialise()
    panel:addToUIManager()
    panel:setAlwaysOnTop(true)
    DeadDropClient.openPanel = panel
end

local function hasCash(player)
    local inventory = player:getInventory()
    for _, fullType in ipairs(CASH) do
        if inventory:getCountTypeRecurse(fullType) > 0 then return true end
    end
    return false
end

local function settings()
    return SandboxVars and SandboxVars.DeadDrop or nil
end

local function enabled()
    local options = settings()
    return not options or options.Enabled ~= false
end

local function freeOrders()
    local options = settings()
    return options and options.FreeOrders == true
end

local function isActiveRadio(radio)
    local device = radio and radio:getDeviceData()
    return device and not device:getIsTelevision()
        and device:getIsTurnedOn() and device:getPower() > 0
end

local function addTooltip(option, description)
    option.toolTip = ISToolTip:new()
    option.toolTip:initialise()
    option.toolTip:setVisible(false)
    option.toolTip.description = description
end

local function unavailable(option, description)
    option.notAvailable = true
    addTooltip(option, description)
end

function DeadDropClient.showResult(response)
    local player = getPlayer()
    if not player or not response then return end

    if response.status == "ok" then
        if response.action == "open" then
            DeadDropOpenPanel.show(response.rarity, response.loot, response.itemId)
        elseif response.action == "claim" then
            if DeadDropClient.openPanel then DeadDropClient.openPanel:reveal() end
        else
            HaloTextHelper.addGoodText(player, "Black market crate delivered.")
        end
    else
        if response.action == "claim" and DeadDropClient.openPanel then
            DeadDropClient.openPanel:destroy()
        end
        HaloTextHelper.addBadText(player, messages[response.status] or "Dead Drop request failed.")
    end
end

local function dispatch(player, command, args)
    if isClient() then
        sendClientCommand(player, MODULE, command, args)
        return
    end

    local response
    if command == "order" then
        response = DeadDropServer.handleOrder(player, args)
    elseif command == "open" then
        response = DeadDropServer.handleOpen(player, args)
    else
        response = DeadDropServer.handleClaim(player, args)
    end
    DeadDropClient.showResult(response)
end

function DeadDropClient.claim(itemId)
    local player = getPlayer()
    if player then dispatch(player, "claim", { itemId = itemId }) end
end

local function orderCrate(player, radio)
    if not isActiveRadio(radio) then
        HaloTextHelper.addBadText(player, messages.radio_off)
        return
    end
    if not freeOrders() and not hasCash(player) then
        HaloTextHelper.addBadText(player, messages.no_money)
        return
    end
    dispatch(player, "order", {
        x = radio:getX(), y = radio:getY(), z = radio:getZ(),
        objectIndex = radio:getObjectIndex(),
    })
end

local function onWorldMenu(playerNum, context, worldObjects, test)
    if not enabled() then return end

    local radio
    for _, object in ipairs(worldObjects) do
        local device = instanceof(object, "IsoWaveSignal") and object:getDeviceData() or nil
        if device and not device:getIsTelevision() then
            radio = object
            break
        end
    end
    if not radio then return end
    if test then return ISWorldObjectContextMenu.setTest() end

    local player = getSpecificPlayer(playerNum)
    local option = context:addOption("Order Black Market Crate", player, orderCrate, radio)
    addTooltip(option, freeOrders() and "Cost: Free (Sandbox debug)." or "Cost: $1.")
    if not isActiveRadio(radio) then
        unavailable(option, messages.radio_off)
    elseif not freeOrders() and not hasCash(player) then
        unavailable(option, messages.no_money)
    end
end

local function isOwnedCrate(player, item)
    if not item or item:getFullType() ~= CRATE then return false end
    local crates = player:getInventory():getAllTypeRecurse(CRATE)
    for i = 0, crates:size() - 1 do
        if crates:get(i):getID() == item:getID() then return true end
    end
    return false
end

local function openCrate(player, crate)
    dispatch(player, "open", { itemId = crate:getID() })
end

local function onInventoryMenu(playerNum, context, items)
    if not enabled() then return end

    local player = getSpecificPlayer(playerNum)
    for _, entry in ipairs(items) do
        local item = instanceof(entry, "InventoryItem") and entry or entry.items[1]
        if isOwnedCrate(player, item) then
            context:addOption("Open Crate", player, openCrate, item)
            return
        end
    end
end

local function onServerCommand(module, command, args)
    if module == MODULE and command == "result" then
        DeadDropClient.showResult(args)
    end
end

Events.OnFillWorldObjectContextMenu.Add(onWorldMenu)
Events.OnFillInventoryObjectContextMenu.Add(onInventoryMenu)
Events.OnServerCommand.Add(onServerCommand)
