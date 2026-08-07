require "Items/ProceduralDistributions"

local GATCHA_MACHINE = "DeadDrop.GatchaMachine"

-- Convenience-store and gas-station counter distributions. The low weights
-- keep the machine uncommon while still allowing it to appear naturally in
-- places that sell lottery tickets.
local targets = {
    { name = "StoreCounterBags", weight = 5 },
    { name = "GasStoreSpecial", weight = 5 },
}

local function addUnique(items, fullType, weight)
    for index = 1, #items, 2 do
        if items[index] == fullType then return end
    end
    table.insert(items, fullType)
    table.insert(items, weight)
end

for _, target in ipairs(targets) do
    local distribution = ProceduralDistributions.list[target.name]
    if distribution and distribution.items then
        addUnique(distribution.items, GATCHA_MACHINE, target.weight)
    end
end
