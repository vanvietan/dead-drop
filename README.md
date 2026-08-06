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

1. Carry at least one `Money`, `Gold Coin`, or `Silver Coin`. Each counts as $1; money bundles do not count.
2. Stand within two tiles of a powered, switched-on world radio.
3. Right-click the radio and choose **Order Black Market Crate**.
4. Right-click the delivered **Black Market Crate** in your inventory and choose **Open Crate**.

The server removes one cash item, rolls the rarity, consumes the crate, and grants the loot. A Project Zomboid-style item reel runs for four seconds, locks onto the server-selected reward for one second, then reveals the full crate contents. Cash is consumed in this order: Money, Gold Coin, Silver Coin.

## Sandbox Options

The **Dead Drop: Black Market Crates** sandbox page can enable or disable the mod. For testing, **Free Orders** skips cash consumption, **Forced Rarity** selects a specific loot tier, and **Debug Logging** writes successful orders and results to the game/server console. Defaults preserve normal gameplay.

## Test

- Try ordering with no cash and with each accepted cash type, including cash inside a nested bag.
- Turn the radio off or remove its power and confirm the menu option is disabled with an explanation.
- In multiplayer, have a client order and open a crate; confirm inventory changes appear on both client and server and the same crate cannot be opened twice.
- Check `~/Zomboid/console.txt` and the server console for new Lua errors.
- The shared loot file asserts at load time that rarity weights total 100 and every roll from 1 through 100 maps to a valid rarity.

Edit loot bundles and rarity weights in `42/media/lua/shared/DeadDrop/DeadDropLoot.lua`.
