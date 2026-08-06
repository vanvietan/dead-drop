require "Moveables/ISMoveableSpriteProps"

DeadDropMoveable = DeadDropMoveable or {}

local ITEM_TYPE = "DeadDrop.GatchaMachine"
local MARKER = "DeadDropGatchaMachine"
local MACHINE_NAME = "Gatcha Machine"
local MACHINE_TEXTURE = "Item_GatchaMachine"
local MACHINE_SPRITES = {
    recreational_01_16 = true,
    recreational_01_17 = true,
    recreational_01_18 = true,
    recreational_01_19 = true,
}

local function spriteName(object)
    local sprite = object and object.getSprite and object:getSprite()
    return sprite and sprite:getName() or nil
end

local function hasMarker(value)
    if not value or not value.getModData then return false end
    local modData = value:getModData()
    return modData and modData[MARKER] == true
end

function DeadDropMoveable.isMachineObject(object)
    local name = spriteName(object)
    return name and MACHINE_SPRITES[name] == true and hasMarker(object)
end

function DeadDropMoveable.isMachineItem(item)
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
    if not name or MACHINE_SPRITES[name] ~= true then return end
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
-- vanilla Dr. Oids cabinet never makes the vanilla cabinet a Dead Drop.
if ISMoveableSpriteProps and not DeadDropMoveable.hooksInstalled then
    DeadDropMoveable.hooksInstalled = true

    local originalPlace = ISMoveableSpriteProps.placeMoveableInternal
    if originalPlace then
        function ISMoveableSpriteProps:placeMoveableInternal(...)
            local args = { ... }
            local isMachine = false
            for _, value in ipairs(args) do
                if DeadDropMoveable.isMachineItem(value) then
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
                if DeadDropMoveable.isMachineObject(value) then
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
