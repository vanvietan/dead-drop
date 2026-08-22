require "Moveables/ISMoveableSpriteProps"

LootBoxMoveable = LootBoxMoveable or {}

local ITEM_TYPE = "LootBox.GatchaMachine"
local MARKER = "LootBoxGatchaMachine"
local MACHINE_NAME = "Gatcha Machine"
local MACHINE_TEXTURE = "Item_GatchaMachine"
local MACHINE_GROUP = "LootBox Gatcha Machine"
local MACHINE_SPRITES = {
    { name = "dead_drop_gatcha_01_0", facing = "W" },
    { name = "dead_drop_gatcha_01_1", facing = "N" },
    { name = "dead_drop_gatcha_01_2", facing = "E" },
    { name = "dead_drop_gatcha_01_3", facing = "S" },
}
local MACHINE_SPRITE_NAMES = {}
for _, def in ipairs(MACHINE_SPRITES) do MACHINE_SPRITE_NAMES[def.name] = true end
local LEGACY_SPRITES = {
    recreational_01_16 = MACHINE_SPRITES[1].name,
    recreational_01_17 = MACHINE_SPRITES[2].name,
    recreational_01_18 = MACHINE_SPRITES[3].name,
    recreational_01_19 = MACHINE_SPRITES[4].name,
}

local function registerMachineSprites(manager)
    for index, def in ipairs(MACHINE_SPRITES) do
        local sprite = manager:AddSprite(def.name, 42190000 + index)
        sprite:setName(def.name)
        local properties = sprite:getProperties()
        properties:set("BlocksPlacement")
        properties:set("CustomItem", ITEM_TYPE)
        properties:set("CustomName", MACHINE_NAME)
        properties:set("Facing", def.facing)
        properties:set("GroupName", MACHINE_GROUP)
        properties:set("IsMoveAble")
        properties:set("PickUpWeight", "200")
        properties:CreateKeySet()
    end
end

Events.OnLoadedTileDefinitions.Add(registerMachineSprites)

local function spriteName(object)
    local sprite = object and object.getSprite and object:getSprite()
    return sprite and sprite:getName() or nil
end

local function hasMarker(value)
    if not value or not value.getModData then return false end
    local modData = value:getModData()
    return modData and modData[MARKER] == true
end

local function migrateLegacyObject(object)
    local name = spriteName(object)
    local replacement = name and LEGACY_SPRITES[name]
    if not replacement or not hasMarker(object) then return name end

    object:setSprite(replacement)
    if isClient and isClient() then object:transmitUpdatedSpriteToServer() end
    if isServer and isServer() then object:transmitUpdatedSpriteToClients() end
    return replacement
end

local function migrateLegacySquare(square)
    local objects = square:getObjects()
    for index = 0, objects:size() - 1 do migrateLegacyObject(objects:get(index)) end
end

Events.LoadGridsquare.Add(migrateLegacySquare)

function LootBoxMoveable.isMachineObject(object)
    local name = migrateLegacyObject(object)
    return name and MACHINE_SPRITE_NAMES[name] == true and hasMarker(object)
end

function LootBoxMoveable.isMachineItem(item)
    if not item then return false end
    return (item.getFullType and item:getFullType() == ITEM_TYPE) or hasMarker(item)
end

local function markItem(item)
    if not item or not item.getModData then return end
    item:getModData()[MARKER] = true
    if item.setName then item:setName(MACHINE_NAME) end
    if item.setTexture and getTexture then
        local texture = getTexture(MACHINE_TEXTURE)
        if texture then item:setTexture(texture) end
    end
end

local function markObject(object)
    if not object or not object.getModData then return end
    local name = spriteName(object)
    if not name or MACHINE_SPRITE_NAMES[name] ~= true then return end
    object:getModData()[MARKER] = true
    if object.transmitModData then object:transmitModData() end
end

local function restoreCustomItem(item)
    if not item then return nil end
    if item.getFullType and item:getFullType() == ITEM_TYPE then
        markItem(item)
        return item
    end

    local container = item.getContainer and item:getContainer() or nil
    local replacement = container and instanceItem(ITEM_TYPE) or nil
    if not replacement then
        markItem(item)
        return item
    end

    container:Remove(item)
    container:AddItem(replacement)
    markItem(replacement)
    if isServer and isServer() then
        sendRemoveItemFromContainer(container, item)
        sendAddItemToContainer(container, replacement)
    end
    return replacement
end

-- B42 performs movable conversion on the authoritative side. Preserve a
-- private marker across both conversions so sharing a visual sprite with the
-- vanilla Dr. Oids cabinet never makes the vanilla cabinet a LootBox.
if ISMoveableSpriteProps and not LootBoxMoveable.hooksInstalled then
    LootBoxMoveable.hooksInstalled = true

    local originalPlace = ISMoveableSpriteProps.placeMoveableInternal
    if originalPlace then
        function ISMoveableSpriteProps:placeMoveableInternal(...)
            local args = { ... }
            local isMachine = false
            for _, value in ipairs(args) do
                if LootBoxMoveable.isMachineItem(value) then
                    isMachine = true
                    break
                end
            end

            local object = originalPlace(self, ...)
            if isMachine then markObject(object) end
            return object
        end
    end

    local originalPickup = ISMoveableSpriteProps.pickUpMoveableInternal
    if originalPickup then
        function ISMoveableSpriteProps:pickUpMoveableInternal(...)
            local args = { ... }
            local isMachine = false
            for _, value in ipairs(args) do
                if LootBoxMoveable.isMachineObject(value) then
                    isMachine = true
                    break
                end
            end

            local item = originalPickup(self, ...)
            if isMachine then item = restoreCustomItem(item) end
            return item
        end
    end
end
