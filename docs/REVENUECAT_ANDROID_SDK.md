# RevenueCat Android SDK path (no Stripe, no backend)

This is the shape for builds that sell through the **native RevenueCat SDK**
(Google Play Billing) instead of the hosted funnel: the app configures the SDK
with the public key, opens the store's own purchase sheet, re-reads ownership,
and grants each purchase exactly once. There is no Stripe, no funnel, no secret,
and no server.

For the hosted web-funnel path, see `REVENUECAT_SETUP.md` and
`REVENUECAT_DASHBOARD_RUNBOOK.md` instead.

## What the code already does

- `plugins`: `addons/revenuecat_bridge/` (AAR + Maven dependency) is enabled in
  `project.godot`; the Android preset carries `gradle_build/min_sdk="24"` and
  `permissions/internet=true`.
- `StoreManager` authority `native`: public key + device App User ID, no secret,
  available only where the Android singleton exists.
- `DiamondShop`: a **BUY** button per pack (native authority) and **RESTORE**.
  The **BUY ONLINE** browser row is absent unless a funnel URL is configured.
- Claims: each purchase is re-read from the provider and recorded once per
  transaction id (`web_store_catalog.gd`, `claim_grain: transaction`), so a
  repeat refresh, restart, or save reload can never double-grant.

## Dashboard steps

You need a RevenueCat account (free tier) and, for real purchases, a Google Play
Console account. Product **identifiers are not suggestions** — they must match
`web_store_catalog.gd` character-for-character.

| Play product id | Entitlement id (RevenueCat) | Grants |
|---|---|---|
| `embermarks_pouch` | `embermarks_pouch` | 60 ember marks |
| `embermarks_cache` | `embermarks_cache` | 180 ember marks |
| `embermarks_bloodstone` | `embermarks_bloodstone` | 420 ember marks |

### Fast loop first: Test Store (no Play Console needed)

Nothing is charged, no Play account is involved, and the SDK simulates the
purchase sheet. Unlimited test purchases.

**0. Create (or open) a RevenueCat project.** Dashboard → project switcher
(top-left) → **+ Create new project** → name it → Create.

**1. Create the Test Store app.**
1. Left nav → **Apps & providers** (older builds label it *Project settings →
   Apps*).
2. **+ New** → in the wizard pick the platform **Test Store** (do *not* pick
   Google Play yet).
3. Name it (e.g. `Embervale (Test Store)`) → Create. The app row now shows a
   **Test Store** badge.

**2. Copy the public SDK key.**
1. Left nav → **API keys** (or the app's page).
2. Find the row for your **Test Store** app: the **public app-specific key**
   starts with `test_`. Copy it.
3. Never copy the secret key (`sk_...`) — the app does not use it and it must
   not ship.

**3. Create the three products.**
1. Left nav → **Product catalog → Products** → **+ New**.
2. Select your **Test Store** app, then fill in one row per pack. Type is
   **Consumable** (repeatable — the SDK consumes each purchase so the pack can
   be bought again; the game's claim grain expects this).

   | Identifier | Type | Display name | Test price (any) |
   |---|---|---|---|
   | `embermarks_pouch` | Consumable | Ember Pouch | 0.99 |
   | `embermarks_cache` | Consumable | Ember Cache | 2.99 |
   | `embermarks_bloodstone` | Consumable | Bloodstone Reserve | 4.99 |

3. Identifiers must be typed exactly: the game requests these strings, and
   anything else comes back as `product_unavailable`.

**4. Create the three entitlements and attach the products.**
1. Left nav → **Product catalog → Entitlements** → **+ New**.
2. Identifier `embermarks_pouch` → Create. Repeat for `embermarks_cache` and
   `embermarks_bloodstone` (same strings).
3. Open each entitlement → **Attach products** → pick the matching product →
   Attach. The entitlement ids are what the SDK reports back as ownership, so
   they must also match the catalog exactly.

**5. Create the default offering.**
1. Left nav → **Product catalog → Offerings** → **+ New** → identifier
   `default` → Create.
2. Inside it → **Add packages** → one package per product. The identifier
   dropdown is subscription-shaped (`$rc_monthly`, `$rc_annual`, …); pick
   **Custom** (last entry) and type `pouch` / `cache` / `bloodstone`.
3. Mark it **Default**.
   **This whole step is optional for the current build**: the app buys by
   product id and reads entitlements, never packages or offerings. If the
   dashboard refuses a Custom package, skip the offering — it only matters for
   paywalls, the hosted funnel, or RevenueCat's own store UI.

**6. Put the key in the build.**
1. Write the shipped defaults resource (one command, gitignored output):
   ```sh
   EMBERVALE_REVENUECAT_PUBLIC_KEY="test_XXXXXXXX" \
   godot --headless --path . --script tools/write_store_defaults.gd
   # -> STORE DEFAULTS WRITTEN
   ```
   It writes `res://store_defaults.tres`. It must be a **resource**: the
   exporter only packs resources, so a plain `.cfg` never reaches the APK.
2. `godot --headless --path . --script tools/verify_revenuecat_setup.gd`
   → `SHIPPED DEFAULTS VALID`.
3. Export the Android build and install it: `adb install -r <apk>`.
   (Editor runs ignore the resource by design, so test on the device.)
4. For a build that must **not** carry the key (public release): `... write_store_defaults.gd -- --clear`.

**7. Run the loop.**
1. Launch → HUD **GLINT** → the shop shows a **BUY** button per pack (that row
   only appears when the native authority is live).
2. Tap **BUY** on Ember Pouch → the Test Store sheet appears → complete it.
3. Marks arrive: the balance must increase by exactly 60.
4. Tap **RESTORE** again → *"No new ownership found · nothing was
   double-granted"*.
5. Buy the same pack twice → two grants (repeatable), one per transaction.
6. For a machine verdict, set the run main scene to
   `res://tests/android_native_store_check.tscn`, export a QA build, and read
   `adb logcat -d | grep QA_NATIVE` → `QA_NATIVE RESULT OK`.

**8. Reset between runs.**
`adb shell pm clear com.devhuang1.embervale` (or uninstall/reinstall) clears the
device identity and the ledger so the next test starts from zero.

### Real purchases: Google Play

1. Play Console → create the app with package `com.devhuang1.embervale`.
2. Play Console → **Monetize → Products → In-app products** → create the three
   products above. They are **one-time products**; do not create subscriptions.
3. RevenueCat → **Apps → + New → Google Play** with the same package name, then
   connect Play with a service account that has Play Developer API access
   (RevenueCat's "Service Credentials" tab walks through it).
4. RevenueCat → **Products** → create/import the three Play products and set
   each product type to **Consumable**, so the SDK consumes a purchase and the
   pack can be bought again.
5. RevenueCat → **Entitlements** → create the three ids above, attach each to
   its product.
6. RevenueCat → **Offerings** → one offering with one package per product → make
   it the **Default Offering**.
7. Copy the app's **public SDK key** (`goog_...`).

> Real purchases only work for installs that came from Play: publish the app to
> an **internal testing** track and install through the Play link. A sideloaded
> APK cannot buy.

## Where the key goes

For an exported Android build, write the gitignored `res://store_defaults.tres`
before exporting (editor/CI ignore it; there is no identity field — every install
mints its own `ev_...`):

```sh
EMBERVALE_REVENUECAT_PUBLIC_KEY="goog_XXXXXXXX" \  # or test_XXXXXXXX
godot --headless --path . --script tools/write_store_defaults.gd
```

`--clear` removes it again. The optional web-path values are written from
`EMBERVALE_REVENUECAT_PROJECT_ID` and `EMBERVALE_STORE_FUNNEL_URL` in the same
command.

There is no secret to configure anywhere, and nothing else is required: no
project id, no funnel URL, no backend.

## Verify

Offline, before a build (validates the shipped file, no network):

```sh
godot --headless --path . --script tools/verify_revenuecat_setup.gd
# -> SHIPPED DEFAULTS VALID
```

On device, the QA scene prints one greppable verdict (see the runbook's
"On-device check" for the build + adb commands):

```
QA_NATIVE authority=native available=true
QA_NATIVE refresh ok=true status=ready ... granted=1
QA_NATIVE RESULT OK
```

Then do the player-facing loop in the shop: **BUY** one pack → sheet completes →
marks arrive; tap **RESTORE** again and it must read *"No new ownership found"*.

## Known limits

- **Desktop cannot buy through the SDK.** The plugin is Android-only, so
  desktop/editor runs cannot exercise the native purchase; use a device (Test
  Store key) for that loop, or the hosted-funnel path for desktop QA.
- **Prices live in the store.** The client shows no price; the purchase sheet
  owns it.
- **Consumables** keep their entitlement active forever after the first
  purchase; that is why grants are keyed by transaction id (already implemented)
  and why every pack is marked Consumable in RevenueCat.
- **Refunds/chargebacks** arrive as RevenueCat webhooks only if you have a
  backend; with the SDK-only shape the ledger is append-only and no negative
  grant path exists. Do not promise refund automation until a backend exists.
