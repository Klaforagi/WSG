# Market stall

Offers refresh every 1,200 seconds on the same time boundaries as potion stock.
All servers running the same configuration generate identical offers. Every player
can buy one of each weapon per refresh; a purchase does not consume another player's stock.
Purchases use coins and go directly into the appropriate inventory.

## Odds and prices

| Slot | Rarity probabilities |
| --- | --- |
| 1 | Common 100% |
| 2 | Uncommon 75%, Rare 25% |
| 3 | Rare 75%, Epic 20%, Legendary 5% |

Slots 2–3 size probabilities: Tiny (80–89%) 15%, Normal (90–110%) 70%, Large (111–149%) 10%,
Giant (150–189%) 4%, King (190–200%) 1%.
Slot 1 favors large weapons: Tiny 2%, Normal 18%, Large 40%, Giant 30%, King 10%.
Normal uses a triangular distribution
peaking at 100%; other tiers pick each integer size equally.

Only slot 3 can be Legendary. A Legendary King-size offer has probability
`0.05 * 0.01 = 0.0005`: 0.05%, or 1 in 2,000 refreshes. Exactly 200% has probability
`0.05 * 0.01 / 11`: approximately 0.004545%, or 1 in 22,000 refreshes.
These odds include any Legendary weapon, not one specific weapon.

Base coin prices through 100%: Common 40, Uncommon 300, Rare 1,000, Epic 5,000,
Legendary 10,000. Set `x = clamp((size - 100) / 100, 0, 1)` and multiply base by
`1 + 3 * (9^x - 1) / 8`. This exponential curve caps at a 300% increase (4x base).
A 150% Legendary costs 17,500; a 200% Legendary costs 40,000 before enchants.
Every market weapon independently has a 25% chance of an enchant, chosen uniformly
from the existing enchant list. Add 25% of the size-adjusted price plus 200 coins,
then, for enchanted Giant/King weapons (150% or larger), add another 500 coins and
multiply the total by 1.5. Round to the nearest 5 coins after all adjustments
(ties round up). For example: 148 → 150, 133 → 135, and 4,609 → 4,610.
A 150% enchanted Legendary costs 33,865; a 200% enchanted Legendary costs 76,050.
Market rolls are final, including unenchanted Ethereal weapons; crate rules are unchanged.
Tune these values in `src/ReplicatedStorage/MarketConfig.lua` without changing crate odds.

## Potion offers and cosmetics

The Potions section follows Weapons, then Trails and Emotes. Weapons and Potions
each show the same refresh countdown in their section header.

Purchases update stock/ownership labels in place, retaining selection and scroll
position; only a new rotation rebuilds the cards. Server stock reservations remain
durable before granting items, but profile flushing runs outside the purchase
response. Weapon/potion cards and details use the same asset lookup as inventory/
hotbar tooltips (including their existing missing-image limitations).
All card prices use the coin icon. Weapon size details are left-aligned and styled
in both panels; Rainbow Trail is the last trail.

- Potion slot 1: Health, Strength, or Speed Potion; five purchases in stock.
- Potion slot 2: a Flask of Wealth, Expertise, or Wisdom; one to three purchases.
- Potion slot 3: Swiftness, Power, or Vitality Elixir; one to three purchases.

Prices and quantities come directly from the potion stall configs/services. Battle
potions currently grant three bottles per purchase; flasks/elixirs grant one.
Market potion stock is per player, persistent, and separate from potion-stall stock.
All purchasable trails cost 2,000 coins and emotes cost 1,000 coins. Existing free
defaults remain owned. Neither category shows description text in the market.

## Migration and validation

The runtime renames existing top-level `SkinsStall`/`CosmeticsStall` models to
`MarketStall` and updates text signs. New place models should be named `MarketStall`
with the existing `PromptPart`. Image/decal signs must be replaced in Studio.
Old skin scripts/configs/UI have been removed. Existing skin DataStores were not erased.
Mob color variation is unrelated and remains enabled.

Run `luau tests/market.spec.luau` for roll bounds, probability sampling, price scaling,
cycle boundaries and datastore claim-transform tests. In Studio test two clients,
successful/insufficient-funds purchases, a repeated purchase after rejoining,
refresh during purchase, and trail/emote previews/equipping at desktop/mobile sizes.

Stock reservations are persisted before granting. If a process terminates between
reservation and inventory/currency saves, the slot stays unavailable for that cycle
(fail-closed against duplicates); the existing separate DataStores do not support an
atomic transaction across stock, currency and weapon inventory. Ordinary rejected
purchases release their reservation. Datastore errors block purchases.
