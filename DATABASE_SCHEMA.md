# Embervale player-data schema

This is the backend contract for the Android sync layer. The Godot client keeps
the local save for offline play and submits intent records; the server owns
currency balances, entitlement validation, and mutation ordering.

## Core tables

| Table | Key fields | Purpose |
|---|---|---|
| `players` | `id`, `account_id`, `schema_version`, `updated_at` | One progression profile per account. |
| `player_currencies` | `player_id`, `gold`, `diamonds`, `updated_at` | Server-authoritative balances. |
| `player_inventory` | `player_id`, `content_id`, `quantity` | Materials, potions, and owned stackable items. |
| `player_equipment` | `player_id`, `slot`, `content_id`, `upgrade_level` | Equipped weapon and armor slots. |
| `player_content` | `player_id`, `content_id`, `category`, `rarity`, `upgrade_level`, `metadata` | Unique weapons, armor, cosmetics, and scanned relics. |
| `player_quests` | `player_id`, `quest_id`, `state`, `progress`, `schema_version` | Quest and chapter progress. |
| `player_scans` | `player_id`, `scans_remaining`, `fragments` | Scan balance and fragments. |
| `purchase_ledger` | `id`, `player_id`, `kind`, `content_id`, `currency`, `amount`, `provider_id` | Auditable purchases, refunds, and entitlements. |
| `mutation_ledger` | `id`, `player_id`, `action`, `payload`, `status`, `created_at` | Idempotent gameplay intents and server results. |

## Invariants

- `content_id` is a stable normalized ID such as `ember_sword`; display names
  never identify saved content.
- `(player_id, mutation_ledger.id)` is unique. Retried requests return the
  original result instead of applying a second mutation.
- Currency values are non-negative and are changed only inside a transaction.
- Inventory quantities and upgrade levels are bounded by server-side rules.
- `provider_id` is unique for a paid purchase; RevenueCat verifies entitlement
  but does not replace the player inventory or currency tables.
- Every response returns the authoritative changed rows plus the latest
  server revision so the Android cache can reconcile safely.

## Intent example

```json
{
  "id": "upgrade-weapon-ember_sword-2",
  "action": "upgrade_weapon",
  "payload": {"item_id": "ember_sword", "level": 2, "gold": 43}
}
```

The server validates ownership, current level, costs, and revision before
committing. The client never submits a replacement gold or diamond balance.
