# Dead Drop: Black Market Supply Crates

MVP mod for Project Zomboid Build 42.19. It uses vanilla in-game items only; there are no real-money transactions.

## Install

1. Copy this project directory to:
   - Windows: `%UserProfile%\Zomboid\Workshop\DeadDropBlackMarket\`
   - macOS/Linux: `~/Zomboid/Workshop/DeadDropBlackMarket/`
2. Confirm that `Contents/mods/DeadDropBlackMarket/common/` and `Contents/mods/DeadDropBlackMarket/42/mod.info` exist.
3. Start Project Zomboid, open **Mods**, and enable **Dead Drop: Black Market Supply Crates**.
4. Enable the mod for a new test save. The Mod ID is `DeadDropBlackMarket`.

For a manually configured multiplayer server, add `DeadDropBlackMarket` to `Mods=` and install the same files on the server and clients. No `WorkshopItems=` value exists until the mod is published to Steam Workshop.

## Use

1. Find a **Gatcha Machine** in a convenience-store or gas-station counter, then place it in the world. It can be picked up and moved back to your base.
2. Carry at least one `Money`, `Gold Coin`, or `Silver Coin`. Each counts as $1; money bundles do not count.
3. Stand within two tiles of the placed machine. It does not need power.
4. Right-click the machine and choose **Open Crate**.

The server removes one cash item, rolls the rarity, and selects one item type from that rarity's pool. A Project Zomboid-style item reel runs for seven seconds, locks onto the server-selected reward for one second, then grants its configured quantity directly. Cash is consumed in this order: Money, Gold Coin, Silver Coin.

## Sandbox Options

The **Dead Drop: Black Market Crates** sandbox page can enable or disable the mod. **Free Orders** skips cash consumption, and **Debug Logging** writes successful openings and results to the game/server console. Each rarity has its own configurable chance, defaulting to **30% Common, 25% Uncommon, 20% Rare, 15% Epic, and 10% Contraband**. If their total is not 100, the values are treated as relative weights and normalized automatically; if all five are zero, the defaults are used.

## Test

- Try opening with no cash and with each accepted cash type, including cash inside a nested bag.
- Confirm a Gatcha Machine can spawn in convenience-store and gas-station counters, be picked up, placed, picked up again, and moved to a base.
- Confirm all four placed orientations show the **Open Crate** action.
- With **Free Orders** enabled, set each rarity chance to 100 in turn (and the others to 0) and confirm all five tiers award exactly one item type with the expected color and quantity.
- Confirm a vanilla Dr. Oids cabinet never shows the action, while a Gatcha Machine keeps its name, icon, and action after repeated pickup/place cycles.
- Confirm radios and the PAWS pinball machine do not show **Open Crate**, and opening from more than two tiles away is rejected.
- In multiplayer, open a crate directly from the machine; confirm inventory changes appear on both client and server and the same request cannot be claimed twice.
- Disconnect during the reel, reconnect, and use a machine again; confirm the same result resumes without consuming more cash.
- Check `~/Zomboid/console.txt` and the server console for new Lua errors.
- The shared loot file asserts at load time that the default rarity weights total 100 and every default roll from 1 through 100 maps to a valid rarity.

Edit single-item pools in `42/media/lua/shared/DeadDrop/DeadDropLoot.lua`; configure rarity chances from the sandbox options.
