require "ISUI/ISWorldObjectContextMenu"
require "ISUI/ISToolTip"
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "DeadDrop/DeadDropLoot"
require "DeadDrop/DeadDropMoveable"

DeadDropClient = DeadDropClient or {}

local MODULE = "DeadDrop"
local REEL_DURATION = 7000
local LOCK_DURATION = 1000
local REVEAL_TIME = REEL_DURATION + LOCK_DURATION
local REEL_ITEM_COUNT = 32

local function reelSoundStep(elapsed)
    local progress = elapsed / REEL_DURATION
    return math.floor((1 - math.pow(1 - progress, 3)) * REEL_ITEM_COUNT)
end

assert(reelSoundStep(0) == 0 and reelSoundStep(REEL_DURATION) == REEL_ITEM_COUNT,
    "[DeadDrop] invalid reel sound timing")

local messages = {
    no_money = "You need $1 in cash.",
    invalid_machine = "That Gatcha Machine is no longer available.",
    too_far = "Move closer to the Gatcha Machine.",
    invalid_request = "That opening request is no longer available.",
    config_error = "Dead Drop loot configuration is invalid.",
    disabled = "Dead Drop is disabled in Sandbox Options.",
}

local rarityColors = {
    Common = { r = 0.62, g = 0.62, b = 0.55 },
    Uncommon = { r = 0.36, g = 0.62, b = 0.38 },
    Rare = { r = 0.30, g = 0.50, b = 0.76 },
    Epic = { r = 0.62, g = 0.30, b = 0.76 },
    Contraband = { r = 0.70, g = 0.18, b = 0.18 },
}

local scanningColor = { r = 0.34, g = 0.78, b = 0.39 }
local uiColors = {
    plastic = { r = 0.82, g = 0.81, b = 0.75 },
    trim = { r = 0.34, g = 0.37, b = 0.38 },
    display = { r = 0.025, g = 0.055, b = 0.04 },
    slot = { r = 0.16, g = 0.18, b = 0.17 },
    red = { r = 0.72, g = 0.10, b = 0.07 },
    blue = { r = 0.06, g = 0.28, b = 0.68 },
}

DeadDropOpenPanel = ISPanel:derive("DeadDropOpenPanel")

function DeadDropOpenPanel:new(rarity, lootText, requestId)
    local width, height = 460, 330
    local panel = ISPanel:new((getCore():getScreenWidth() - width) / 2,
        (getCore():getScreenHeight() - height) / 2, width, height)
    setmetatable(panel, self)
    self.__index = self
    panel.rarity = rarity or "Common"
    panel.requestId = requestId
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
    assert(#panel.loot <= 4, "[DeadDrop] roulette panel supports at most four loot entries")
    panel.reel = {}
    local candidates = {}
    for _, pool in pairs(DeadDropLoot.itemPools) do
        for _, entry in ipairs(pool) do
            local scriptItem = ScriptManager.instance:FindItem(entry.fullType)
            if scriptItem then table.insert(candidates, scriptItem:getNormalTexture()) end
        end
    end
    for _ = 1, REEL_ITEM_COUNT do
        table.insert(panel.reel, candidates[ZombRand(#candidates) + 1])
    end
    table.insert(panel.reel, panel.loot[1] and panel.loot[1].texture or nil)
    panel.startedAt = getTimestampMs()
    panel.lastSoundStep = -1
    panel.revealed = false
    panel.backgroundColor = { r = uiColors.plastic.r, g = uiColors.plastic.g,
        b = uiColors.plastic.b, a = 0.98 }
    panel.borderColor = { r = uiColors.trim.r, g = uiColors.trim.g,
        b = uiColors.trim.b, a = 1 }
    panel:setWantKeyEvents(true)
    return panel
end

function DeadDropOpenPanel:initialise()
    ISPanel.initialise(self)
    self.closeButton = ISButton:new(self.width / 2 - 55, self.height - 42, 110, 28,
        "CLOSE", self, DeadDropOpenPanel.destroy)
    self.closeButton:initialise()
    self.closeButton:instantiate()
    self.closeButton.backgroundColor = { r = uiColors.blue.r, g = uiColors.blue.g,
        b = uiColors.blue.b, a = 1 }
    self.closeButton.backgroundColorMouseOver = { r = 0.10, g = 0.42, b = 0.88, a = 1 }
    self.closeButton.borderColor = { r = uiColors.trim.r, g = uiColors.trim.g,
        b = uiColors.trim.b, a = 1 }
    self.closeButton:setVisible(false)
    self:addChild(self.closeButton)
end

function DeadDropOpenPanel:update()
    ISPanel.update(self)
    self:setX((getCore():getScreenWidth() - self.width) / 2)
    self:setY((getCore():getScreenHeight() - self.height) / 2)
    local now = getTimestampMs()
    local elapsed = now - self.startedAt
    if not self.revealed and elapsed < REEL_DURATION then
        local soundStep = reelSoundStep(elapsed)
        if soundStep ~= self.lastSoundStep then
            self.lastSoundStep = soundStep
            getSoundManager():playUISound("UISelectListItem")
        end
    end
    if not self.revealed and elapsed >= REVEAL_TIME
            and (not self.nextClaimAt or now >= self.nextClaimAt) then
        self.nextClaimAt = now + 500
        DeadDropClient.claim(self.requestId)
    end
end

function DeadDropOpenPanel:reveal()
    if self.revealed then return end
    self.revealed = true
    if self.rarity == "Epic" or self.rarity == "Contraband" then
        getSoundManager():playUISound("UIAchievement")
    end
    self.closeButton:setVisible(true)
end

function DeadDropOpenPanel:prerender()
    ISPanel.prerender(self)
    local elapsed = getTimestampMs() - self.startedAt
    -- Do not expose the result through the accent color before the reveal.
    local color = self.revealed and self.color or scanningColor
    local title = elapsed < REEL_DURATION and "CAPSULE SELECTOR // CYCLING"
        or (not self.revealed and "CAPSULE SELECTOR // LOCKED"
            or string.upper(self.rarity) .. " CACHE DISPENSED")

    self:drawRect(18, 16, self.width - 36, 46, 1,
        uiColors.display.r, uiColors.display.g, uiColors.display.b)
    self:drawRectBorder(18, 16, self.width - 36, 46, 1,
        uiColors.trim.r, uiColors.trim.g, uiColors.trim.b)
    self:drawRect(26, 33, 9, 9, 1, uiColors.red.r, uiColors.red.g, uiColors.red.b)
    self:drawRect(40, 33, 9, 9, 1, uiColors.blue.r, uiColors.blue.g, uiColors.blue.b)
    self:drawRect(58, 54, self.width - 84, 2, 1, color.r, color.g, color.b)
    self:drawTextCentre(title, self.width / 2 + 12, 29,
        color.r, color.g, color.b, 1, UIFont.Medium)

    if not self.revealed then
        local reelLeft, reelRight, slotWidth = 30, self.width - 30, 88
        local progress = math.min(elapsed / REEL_DURATION, 1)
        local eased = 1 - math.pow(1 - progress, 3)
        local target = reelLeft + (#self.reel - 1) * slotWidth - self.width / 2
        local offset = target * eased

        local reelTop, reelHeight = 68, 92
        self:drawRect(reelLeft, reelTop, reelRight - reelLeft, reelHeight,
            1, uiColors.display.r, uiColors.display.g, uiColors.display.b)
        self:drawRectBorder(reelLeft, reelTop, reelRight - reelLeft, reelHeight,
            1, uiColors.trim.r, uiColors.trim.g, uiColors.trim.b)

        -- Keep partially-visible slots inside the reel viewport. The extra
        -- 44px in the visibility check makes slots enter smoothly, but without
        -- a stencil their backgrounds and icons spill over the panel edges.
        self:setStencilRect(reelLeft, reelTop, reelRight - reelLeft, reelHeight)
        for index, texture in ipairs(self.reel) do
            local x = reelLeft + (index - 1) * slotWidth - offset
            if x > reelLeft - 44 and x < reelRight + 44 then
                self:drawRect(x - 36, 74, 72, 80, 1,
                    uiColors.slot.r, uiColors.slot.g, uiColors.slot.b)
                self:drawRectBorder(x - 36, 74, 72, 80, 1,
                    uiColors.trim.r, uiColors.trim.g, uiColors.trim.b)
                if texture then
                    self:drawTextureScaledAspect(texture, x - 25, 87, 50, 50, 1, 1, 1, 1)
                end
            end
        end
        self:clearStencilRect()
        self:drawRect(self.width / 2 - 38, 68, 76, 3, 1,
            uiColors.red.r, uiColors.red.g, uiColors.red.b)
        self:drawRect(self.width / 2 - 38, 157, 76, 3, 1,
            uiColors.blue.r, uiColors.blue.g, uiColors.blue.b)
        self:drawRect(128, 169, self.width - 256, 27, 1,
            uiColors.display.r, uiColors.display.g, uiColors.display.b)
        local status = elapsed < REEL_DURATION and "SELECTING " .. math.floor(progress * 100) .. "%"
            or "SELECTION READY"
        self:drawTextCentre(status, self.width / 2, 176,
            scanningColor.r, scanningColor.g, scanningColor.b, 1, UIFont.Small)
    elseif self.revealed then
        self:drawRect(30, 72, self.width - 60, 188, 1,
            uiColors.display.r, uiColors.display.g, uiColors.display.b)
        self:drawRectBorder(30, 72, self.width - 60, 188, 1,
            uiColors.trim.r, uiColors.trim.g, uiColors.trim.b)
        self:drawTextCentre("DISPENSED CONTENTS", self.width / 2, 86,
            color.r, color.g, color.b, 1, UIFont.Small)
        for index, item in ipairs(self.loot) do
            if item.texture then
                self:drawTextureScaledAspect(item.texture, 118, 108 + (index - 1) * 40,
                    32, 32, 1, 1, 1, 1)
            end
            self:drawText(item.name .. " x" .. item.quantity, 166, 116 + (index - 1) * 40,
                0.86, 0.85, 0.78, 1, UIFont.Small)
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

function DeadDropOpenPanel.show(rarity, loot, requestId)
    if DeadDropClient.openPanel then DeadDropClient.openPanel:destroy() end
    local panel = DeadDropOpenPanel:new(rarity, loot, requestId)
    panel:initialise()
    panel:addToUIManager()
    panel:setAlwaysOnTop(true)
    DeadDropClient.openPanel = panel
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

local function isGatchaMachine(object)
    return DeadDropMoveable.isMachineObject(object)
end

local function addTooltip(option, description)
    option.toolTip = ISToolTip:new()
    option.toolTip:initialise()
    option.toolTip:setVisible(false)
    option.toolTip.description = description
end

function DeadDropClient.showResult(response)
    local player = getPlayer()
    if not player or not response then return end

    if response.status == "ok" then
        if response.action == "open" then
            DeadDropOpenPanel.show(response.rarity, response.loot, response.requestId)
        elseif response.action == "claim" then
            if DeadDropClient.openPanel then DeadDropClient.openPanel:reveal() end
        end
    else
        if response.action == "claim" and response.status == "pending" then return end
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
    if command == "open" then
        response = DeadDropServer.handleOpen(player, args)
    else
        response = DeadDropServer.handleClaim(player, args)
    end
    DeadDropClient.showResult(response)
end

function DeadDropClient.claim(requestId)
    local player = getPlayer()
    if player then dispatch(player, "claim", { requestId = requestId }) end
end

local function openCrate(player, machine)
    if not isGatchaMachine(machine) then
        HaloTextHelper.addBadText(player, messages.invalid_machine)
        return
    end
    dispatch(player, "open", {
        x = machine:getX(), y = machine:getY(), z = machine:getZ(),
        objectIndex = machine:getObjectIndex(),
    })
end

local function onWorldMenu(playerNum, context, worldObjects, test)
    if not enabled() then return end

    local machine
    for _, object in ipairs(worldObjects) do
        if isGatchaMachine(object) then
            machine = object
            break
        end
    end
    if not machine then return end
    if test then return ISWorldObjectContextMenu.setTest() end

    local player = getSpecificPlayer(playerNum)
    local option = context:addOption("Open Crate", player, openCrate, machine)
    addTooltip(option, freeOrders() and "Cost: Free (Sandbox debug)." or "Cost: $1.")
end

local function onServerCommand(module, command, args)
    if module == MODULE and command == "result" then
        DeadDropClient.showResult(args)
    end
end

Events.OnFillWorldObjectContextMenu.Add(onWorldMenu)
Events.OnServerCommand.Add(onServerCommand)
