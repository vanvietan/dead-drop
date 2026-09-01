# LootBox

MVP mod for Project Zomboid Build 42.20. Its default pools use vanilla items, with optional Workshop item support; there are no real-money transactions.

## Install

1. Copy this project directory to:
   - Windows: `%UserProfile%\Zomboid\Workshop\LootBox\`
   - macOS/Linux: `~/Zomboid/Workshop/LootBox/`
2. Confirm that `Contents/mods/LootBox/common/` and `Contents/mods/LootBox/42/mod.info` exist.
3. Start Project Zomboid, open **Mods**, and enable **LootBox**.
4. Enable the mod for a new test save. The Mod ID is `LootBox`.

For a manually configured multiplayer server, add `LootBox` to `Mods=` and install the same files on the server and clients. No `WorkshopItems=` value exists until the mod is published to Steam Workshop.

## Use

1. Find a deployed **Gatcha Machine** in a convenience store or gas station. Each eligible building has a fixed 100% chance to receive one, and no building receives more than one. The machine can be used there or picked up and moved back to your base.
2. Carry enough `Money`, `Gold Coin`, or `Silver Coin` items to cover the spin cost. The default cost is $10; each item counts as $1, mixed currency types are accepted, and money bundles do not count.
3. Stand within two tiles of the placed machine. It does not need power.
4. Right-click the machine and choose **Open Crate**.

Machines are deployed directly into the world rather than appearing as container loot. A building's deployment result is saved permanently, so reloading the area does not create duplicates and moving or destroying its machine does not spawn a replacement. Existing saves are supported: eligible stores are processed as their squares load, while machine items and placed machines that already exist are left untouched.

The server removes the configured number of cash items, rolls the rarity, and selects one item type from that rarity's pool. A Project Zomboid-style item reel runs for seven seconds, locks onto the server-selected reward for one second, then grants its configured quantity directly. Cash is consumed in this order: Money, Gold Coin, Silver Coin.

## Sandbox Options

The **LootBox** sandbox page can enable or disable the mod. **Cost Per Spin ($)** accepts values from 1 to 100 and defaults to **$10**. **Free Orders** skips cash consumption, and **Debug Logging** writes successful openings and results to the game/server console. Each rarity has its own configurable chance, defaulting to **30% Common, 25% Uncommon, 20% Rare, 15% Epic, and 10% Contraband**. If their total is not 100, the values are treated as relative weights and normalized automatically; if all five are zero, the defaults are used.

Each rarity also has an optional item-pool field. Use `Module.Item:Quantity` entries separated by semicolons, for example `Base.Axe:1;Brita.AR15:2`. A non-empty valid field replaces that rarity's default pool; blank fields keep the defaults. Quantities must be whole numbers from 1 to 100. Invalid or unavailable items are ignored, and a custom pool with no valid items falls back to the default pool. Repeat an entry to give it additional equal-probability slots.

Items from other Workshop mods use their Script FullType, not their Steam Workshop ID. Enable and install each source mod on the server and every client by adding its Mod ID to `Mods=` and its Workshop ID to `WorkshopItems=`. LootBox does not declare these optional source mods in `require=`.

## Test

- With the default $10 cost, confirm that 9 cash items are rejected without being consumed and 10 are accepted and consumed. Test each accepted cash type, mixed currency types, and cash inside a nested bag.
- Change **Cost Per Spin ($)** and confirm the tooltip, insufficient-cash message, and amount consumed use the configured value.
- Confirm eligible convenience-store and gas-station buildings receive at most one deployed Gatcha Machine, container loot never contains a new machine, and the deployed machine can be picked up, placed, picked up again, and moved to a base.
- Reload an eligible store and restart the server; confirm it never receives a duplicate. Pick up or destroy its machine and confirm no replacement appears.
- Load an existing save after updating; confirm newly processed stores can deploy machines while existing machine items and placed machines remain intact.
- Confirm all four placed orientations show the **Open Crate** action.
- With **Free Orders** enabled, set each rarity chance to 100 in turn (and the others to 0) and confirm all five tiers award exactly one item type with the expected color and quantity.
- Configure a rarity with vanilla and Workshop item FullTypes; confirm valid entries replace its defaults, appear in the reel, and grant the configured quantity.
- Include malformed, unavailable, and out-of-range entries; confirm they are ignored, logged once, and an all-invalid pool falls back to defaults without consuming money on an error.
- Confirm a vanilla Dr. Oids cabinet never shows the action, while a Gatcha Machine keeps its name, icon, and action after repeated pickup/place cycles.
- Confirm radios and the PAWS pinball machine do not show **Open Crate**, and opening from more than two tiles away is rejected.
- In multiplayer, open a crate directly from the machine; confirm inventory changes appear on both client and server and the same request cannot be claimed twice.
- Disconnect during the reel, reconnect, and use a machine again; confirm the same result resumes without consuming more cash.
- Check `~/Zomboid/console.txt` and the server console for new Lua errors.
- The shared loot file asserts at load time that the default rarity weights total 100 and every default roll from 1 through 100 maps to a valid rarity.

Edit default pools in `42/media/lua/shared/LootBox/LootBoxLoot.lua`; configure rarity chances and optional replacement pools from the sandbox options.
