# RevenueCat web store — setup, demo, and limits

Embervale sells **ember marks** (the cosmetic currency) through a hosted
RevenueCat Funnel backed by Stripe. The app then asks RevenueCat what the
customer owns and records any new pack in the gameplay ledger.

This document is the operator's guide: dashboard setup, device configuration,
the demo script, and the limits a reviewer should know about.

> Selling through the native Android SDK (Google Play) instead of the hosted
> funnel? Use `REVENUECAT_ANDROID_SDK.md` — this document covers the web path.

## Why web first

The web funnel is the shipping default and the demo path: it needs no store
account, no native SDK, and no Play Console track, and it satisfies the
mandatory requirement ("the RevenueCat SDK powers at least one purchase") while
staying fully testable headlessly.

A native Android bridge now exists behind the same seam as an additive step
(`addons/revenuecat_bridge/` + `android-plugin/revenuecat_bridge/`): it
configures the SDK with the **public** key, reads entitlements and consumable
transactions, and can start a store purchase. It carries no secret, and the
claim path it feeds is the same one the web funnel uses. Native store products
(Play Console) are still an operator step; the web funnel is what ships.

## Architecture

```
DiamondShop (UI)
    |  BUY ONLINE / RESTORE
    v
StoreManager (autoload)  --------------------------------> gameplay ledger
    |  entitlement refresh                                  (GameState.purchase_ledger)
    v
EntitlementAuthority  (one of:)
    * BACKEND  -> BackendApiClient -> your server -> RevenueCat REST v2   [shipping]
    * NATIVE   -> RevenueCatBridge (Android AAR, public SDK key)          [device]
    * DIRECT   -> RevenueCat REST v2 with a local secret key              [editor/debug only]
    v
RevenueCatApiClient (pure request + response shaping, no HTTP, no credentials)
```

`res://store_defaults.tres` (gitignored, shipped in the build, written by
`tools/write_store_defaults.gd`) supplies the non-secret values on targets that
have no environment, i.e. Android.

Key properties:

- **Offline and unconfigured are no-ops.** With no store config the game plays
  exactly as before; the shop shows *"Online packs are not configured in this
  build"* and every local path still works.
- **Grants are idempotent.** Each pack maps to one RevenueCat entitlement
  (`scripts/systems/web_store_catalog.gd`). The claim key
  `revenuecat:<entitlement>:<expiry>` is recorded on the ledger row, so a
  refresh loop, a restart, or a save reload can never double-grant.
- **Provider state never replaces the gameplay database.** A confirmed
  entitlement appends an ownership row; it does not overwrite progress, and
  nothing is inferred from a client-owned balance.

## Secret key policy

RevenueCat **v2 secret keys** (`sk_...`) may not appear in client code — their
own documentation says so, and this repository is public. Therefore:

- The shipping authority is the **backend** and authenticates with an
  app-scoped bearer token. The secret stays on the server.
- The **direct** authority exists for editor and debug-device QA only. It
  refuses to activate in a release export (`StoreManager._direct_secret_allowed`),
  and the key is read **only** from an environment variable — never from a file
  in the repository, never from a committed config.

If a key is ever exposed, revoke it in the RevenueCat dashboard (Project
settings → API keys) and create a new one.

## Security properties

- **Secret keys never ship.** A release export cannot resolve the direct
  authority at all (`StoreSecurity.direct_authority_allowed`), a backend
  authority drops the secret from memory as soon as it is selected, and the
  repository is scanned for secret-shaped values by
  `tests/test_store_security_contract.gd`.
- **Host allow-list.** The funnel URL must be HTTPS, on default port, with no
  userinfo, fragment, or query, and on an allow-listed host (`signup.cat` for
  funnels, `api.revenuecat.com` for the API). A custom domain must be added to
  `StoreSecurity.ALLOWED_FUNNEL_HOSTS` deliberately.
- **Redirects are refused.** `max_redirects = 0` and any 3xx is treated as a
  refusal, so the `Authorization` header is never replayed to wherever a
  response points. The response body is capped at the engine level too.
- **Header injection is blocked.** A credential containing CR, LF, space, tab,
  or non-ASCII is refused before it can reach a request header.
- **Fail closed.** A rejected configuration retains nothing and the store
  reports unavailable; it never half-configures.
- **Claim keys cannot be widened.** A one-time pack is keyed by entitlement
  alone, so a later body carrying a different `expires_at` cannot mint a second
  grant. Expiring tiers key on the expiry (one grant per period).
- **Persisted rows are not trusted.** A ledger row whose provider fields are not
  internally consistent with the catalog loses those fields on load, so an
  edited save can neither fabricate ownership nor block a real claim.
- **Numeric expiries are never promoted.** Only a null/absent `expires_at` means
  lifetime; `0`, the epoch, and past values are treated as lapsed.
- **No support-export leak.** `build_data_export()` output is asserted free of
  secret-shaped values, and store sources are scanned so no log call
  interpolates a credential.

Known local-only caveat: a save file on a rooted device can still be edited to
change a diamond balance. Real authority is the provider; the rules above stop
tampering from being *amplified* by the store path.

## Dashboard setup

1. Create a RevenueCat project. Copy the **project id** (`proj...`).
2. Connect Stripe under **Web → Billing**. Products, pricing, tax, and receipts
   stay owned by Stripe/RevenueCat — this repository deliberately hardcodes no
   prices.
3. Create three one-time **products** and attach each to an **entitlement**
   whose identifier matches `web_store_catalog.gd`:
   - `embermarks_pouch` → 60 ember marks
   - `embermarks_cache` → 180 ember marks
   - `embermarks_bloodstone` → 420 ember marks
4. Put the three products in one **offering**, then build a **Funnel** with a
   checkout step.
5. Create a **web purchase link** for that funnel. RevenueCat appends the App
   User ID as a path segment
   (`https://signup.cat/<link_id>/<app_user_id>`), which is exactly what
   `StoreManager.checkout_url()` builds.
6. Note the funnel base URL — the part **before** the App User ID.

## Device / editor configuration

Non-secret values can live in `user://store.cfg`; secrets come from the
environment only.

| Variable | Purpose |
|---|---|
| `EMBERVALE_REVENUECAT_PROJECT_ID` | RevenueCat project id (`proj...`) |
| `EMBERVALE_STORE_FUNNEL_URL` | hosted funnel base, e.g. `https://signup.cat/abc123` |
| `EMBERVALE_STORE_BACKEND_URL` | backend proxy base URL (shipping authority) |
| `EMBERVALE_STORE_ACCESS_TOKEN` | app-scoped bearer token for the backend |
| `EMBERVALE_REVENUECAT_SECRET` | `sk_...` — **editor/debug only**, local QA |

**Environment variables exist on desktop and in the editor only.** Android does
not pass them to the app, so an exported build reads the non-secret values from
a shipped `res://store_defaults.tres` instead, written in one command:

```sh
EMBERVALE_REVENUECAT_PROJECT_ID="projXXXXXXXX" \
EMBERVALE_STORE_FUNNEL_URL="https://signup.cat/<link_id>" \
EMBERVALE_REVENUECAT_PUBLIC_KEY="goog_XXXXXXXX" \
godot --headless --path . --script tools/write_store_defaults.gd
```

It is a **resource** on purpose: the exporter only packs resources, so a plain
`.cfg` in the project root would silently not exist inside the APK.

- **Precedence** is build defaults -> device file (`user://store.cfg`) ->
  environment. Each later source overrides per field; an empty field never
  clears an earlier source, while a malformed or hostile value fails closed and
  clears the field it attacked.
- **Identity never ships.** A `customer_id` in the defaults file is ignored —
  every install mints its own `ev_...` id into `user://store.cfg`, so two
  installs can never share one purchase history.
- **Editor and CI ignore the file.** It is only read in an exported build, so a
  developer's local defaults can never change editor or test behavior.
- The file is **gitignored** (`store_defaults.tres`): a sandbox funnel URL must
  never be committed, and `tests/test_store_security_contract.gd` fails the
  build if the ignore rule is removed. The secret scanner also refuses a
  `sk_...` value if one is ever pasted into it.

With no store config the game plays exactly as before; the direct authority is
editor/debug-only by design, and a device build uses the native reader, the
backend proxy, or nothing at all.

Direct-authority desktop QA (debug build):

```sh
EMBERVALE_REVENUECAT_PROJECT_ID=projXXXXXXXX \
EMBERVALE_STORE_FUNNEL_URL=https://signup.cat/<link_id> \
EMBERVALE_REVENUECAT_SECRET=sk_XXXXXXXX \
godot --path . scenes/main/main.tscn
```

Backend authority (shipping shape, no secret on the device): set
`EMBERVALE_STORE_BACKEND_URL` and `EMBERVALE_STORE_ACCESS_TOKEN`, and have the
server expose:

```
GET {backend}/entitlements/active?customer_id=<id>
-> { "items": [ { "entitlement_id": "...", "expires_at": null } ] }
```

That is the same shape as RevenueCat's `active_entitlements` response, so one
parser serves both authorities.

## Demo script (Shipaton video, under 2 minutes)

1. Open the Glintmonger's Case. Point at the online-store row and the
   RESTORE button: *provider-connected, no price duplicated in the client*.
2. Tap **BUY ONLINE**. The hosted funnel opens in the browser showing the three
   packs.
3. Complete a purchase.
4. Return to the app, tap **RESTORE**. The message reads
   "1 pack delivered · +180 ember marks".
5. Tap RESTORE again on camera. It reads "No new ownership found · nothing was
   double-granted" — that is the idempotency proof.
6. Spend the ember marks on a cosmetic to close the loop.

## Android build requirements

- `permissions/internet=true` in `export_presets.cfg` — **verified as the only
  network permission the store needs, and required**: without it Android
  silently blocks every request and no purchase can ever be confirmed. Every
  other permission stays off.
- Cleartext stays blocked. The Godot 4.7.2 release template sets no
  `usesCleartextTraffic` and no `networkSecurityConfig`, so Android 9+ (API 28+)
  denies plain HTTP by default. Confirm on the shipped APK before release:

  ```sh
  aapt2 dump xmltree --file AndroidManifest.xml app-release.apk | grep -i cleartext
  ```

  An empty result means the platform default applies.
- `allowBackup=false` in the template, so app-private state is not extractable
  through an ADB backup.

## Verification

```sh
godot --headless --path . --script tests/test_revenuecat_entitlements.gd
godot --headless --path . --script tests/test_monetization_safety_audit.gd
godot --headless --path . --script tests/test_release_checklist.gd
```

The entitlement suite runs with no network: request building, auth scoping,
response parsing, every HTTP error class, the catalog, claim idempotency, and a
save/load round trip that proves a claimed pack is not re-granted.

## Known limits and the upgrade path

- **Repeat purchases of the same tier are not supported.** One-time tiers key
  their claim on the entitlement alone, so a second purchase of the same tier
  would be deduplicated. Repeatable packs need
  `GET /v2/projects/{id}/customers/{id}/purchases` and per-purchase claim keys.
- **A custom funnel domain needs a policy edit.** Unknown hosts are refused, so
  the domain must be added to `StoreSecurity.ALLOWED_FUNNEL_HOSTS` before it can
  be opened or trusted.
- **Restore on a new device needs the account.** The device identity lives in
  `user://store.cfg`; without a login the same customer id is not recovered.
  Set an account so `AccountSession` supplies the id, or use Redemption Links.
- **Native store products still need the Play Console.** The Android bridge is
  wired (configure, read entitlements/transactions, start a purchase) and can be
  exercised with a RevenueCat Test Store key on device without Play Console
  products; real Play Billing needs the products published in the store track.
- **The backend proxy does not exist yet.** Until it does, the direct authority
  covers device QA and the demo. Only use it with a debug export.
