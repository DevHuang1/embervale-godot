# RevenueCat dashboard runbook

Everything the code expects, in the order the dashboard wants it. Follow Path A
unless you already have products in Stripe.

> No Stripe? Use the Android SDK path in `REVENUECAT_ANDROID_SDK.md`; the steps
> below are for the hosted web funnel.

Target: **3 one-time products → 3 entitlements → 1 offering → 1 purchase link.**
Roughly 20–30 minutes. Free (RevenueCat's free tier covers this; Stripe charges
nothing until money actually moves).

The entitlement identifiers are **not** suggestions — they are hard-coded in
`scripts/systems/web_store_catalog.gd` and must match exactly:

| Entitlement ID | Product | Grants |
|---|---|---|
| `embermarks_pouch` | Ember Pouch | 60 ember marks |
| `embermarks_cache` | Ember Cache | 180 ember marks |
| `embermarks_bloodstone` | Bloodstone Reserve | 420 ember marks |

## Path A — RevenueCat Billing (recommended, no Stripe products)

Products are created **in the RevenueCat dashboard**; Stripe is only the payment
gateway, so you skip setting up Stripe products and importing them.

1. **Create the project.** Copy the **project id** (`proj...`) — that is
   `EMBERVALE_REVENUECAT_PROJECT_ID`.
2. **Connect Stripe.** Project → *Web* (lower section of the dashboard) →
   connect a Stripe account. Project owner only. A Stripe **sandbox** or
   **test mode** is enough to test and to record the demo; you do not need a
   verified live account.
3. **Create the web config.** Still under *Web* → *Create a web config* →
   RevenueCat Billing. Required: **Stripe account**, **default currency**,
   **app name** (shown in checkout/emails), **support email**. Leave
   *Redemption Links* off — this integration passes an identified App User ID.
4. **Create the three products.** *Product catalog → Products* → select your
   RevenueCat Billing config → **+ New**, once per row above. Use
   **non-consumable** product type and set a price for your default currency.
   Product identifiers are yours to choose; the **entitlement** is what the code
   matches, so name them for humans.
5. **Create the three entitlements.** *Product catalog → Entitlements* →
   **+ New** for each ID in the table. Copy them character-for-character.
6. **Attach each product to its entitlement.** Open the entitlement →
   *Products* → **Attach** → pick the matching product.
7. **Create the offering.** *Product catalog → Offerings* → **+ New** → add a
   package per product → mark it the **Default Offering** (funnels and links
   use it by default).
8. **Create the purchase link.** *Funnels → Purchase Links* → new link →
   select the Offering and your billing config → publish.
9. **Copy the URL.** You get two:
   - **Sandbox** — for testing and for the demo recording.
   - **Production** — for real customers.

   Paste the base (everything up to but **not** including the App User ID) into
   `EMBERVALE_STORE_FUNNEL_URL`. The app appends the customer id itself.

> Never distribute the sandbox URL — anyone holding it can "buy" for free with a
> Stripe test card.

## Path B — Stripe Billing

Same shape, different order: create products and prices in **Stripe** → in
RevenueCat create a *Stripe* web config → *Product catalog → Products* →
select the Stripe config → **Import** → pick products and prices → then steps
5–9 above (entitlements, attach, offering, purchase link).

## Where each value goes

| Value | Desktop / editor QA | Exported Android build |
|---|---|---|
| project id (`proj...`) | `EMBERVALE_REVENUECAT_PROJECT_ID` | written into `res://store_defaults.tres` |
| funnel base URL | `EMBERVALE_STORE_FUNNEL_URL` | written into `res://store_defaults.tres` |
| public SDK key (`goog_...`) | `EMBERVALE_REVENUECAT_PUBLIC_KEY` | written into `res://store_defaults.tres` |
| secret key (`sk_...`) | `EMBERVALE_REVENUECAT_SECRET` (never shipped) | — not allowed |
| App User ID (`ev_...`) | `user://store.cfg` (auto-minted) | `user://store.cfg` (auto-minted) |

For a device build, write the shipped defaults **before exporting** (gitignored,
ignored by editor/CI runs, and a **resource** because the exporter does not pack
plain files):

```sh
EMBERVALE_REVENUECAT_PROJECT_ID="projXXXXXXXX" \
EMBERVALE_STORE_FUNNEL_URL="https://signup.cat/<link_id>" \
EMBERVALE_REVENUECAT_PUBLIC_KEY="goog_XXXXXXXX" \
godot --headless --path . --script tools/write_store_defaults.gd
# -> STORE DEFAULTS WRITTEN   (remove again with: -- --clear)
```

## On-device check (native reader)

The native authority only resolves where the Android plugin exists, so verify it
on a device:

1. Write `store_defaults.tres` (above) with the public SDK key. The
   `RevenueCatBridge` plugin is already enabled in `project.godot`, and the
   Android preset carries `gradle_build/min_sdk="24"` and
   `permissions/internet=true`.
2. For a QA build only, point the run main scene at
   `res://tests/android_native_store_check.tscn` (*Project Settings →
   Application → Run → Main Scene*, or a QA export preset). Never put that in a
   release preset.
3. Install and read the verdict:

```sh
adb install -r <qa-build>.apk
adb shell monkey -p com.devhuang1.embervale -c android.intent.category.LAUNCHER 1
adb logcat -d | grep QA_NATIVE
```

Expected: `QA_NATIVE authority=native available=true`, then either
`QA_NATIVE RESULT OK` after a refresh line, or `FAIL <stage>`
(`store_unavailable`, `refresh`, …). Start with a RevenueCat **Test Store key**:
the SDK then simulates purchases without any Play Console product.

## Verify

```sh
EMBERVALE_REVENUECAT_PROJECT_ID=projXXXXXXXX \
EMBERVALE_REVENUECAT_SECRET=sk_XXXXXXXX \
EMBERVALE_STORE_CUSTOMER_ID=ev_XXXXXXXX \
EMBERVALE_STORE_FUNNEL_URL=https://pay.rev.cat/<your-link> \
godot --headless --path . --script tools/verify_revenuecat_setup.gd
```

- Secret key: *Project settings → API keys → + New*, version **V2**, permission
  `customer_information:customers:read`. It starts with `sk_`.
- `EMBERVALE_STORE_CUSTOMER_ID`: the App User ID the purchase belongs to. The
  app's own identity is in `user://store.cfg` → `customer_id` (it looks like
  `ev_...`); on desktop that file is under
  `~/Library/Application Support/Godot/app_userdata/Embervale Mobile/`.
- The checker reads the same catalog, builder and parser the game uses, and it
  is read-only — safe to run before a demo.

A pass prints `SETUP CHECK PASSED`. `0 active entitlements` means the dashboard
is right but that customer has not bought anything yet.

## Testing without spending money

1. Open the **Sandbox** link with the App User ID appended, or just let the app
   open it via **BUY ONLINE**.
2. Pay with Stripe's test card `4242 4242 4242 4242`, any future expiry, any CVC.
3. Return to the app and tap **RESTORE**. The message should read
   *"1 pack delivered · +180 ember marks"*.
4. Tap **RESTORE** again on camera — *"No new ownership found · nothing was
   double-granted"*.

### Verifying the app half before Stripe exists

You can grant an entitlement straight through the API to test the whole
app-side path with no checkout at all:

```sh
curl -X POST \
  -H "Authorization: Bearer sk_XXXXXXXX" \
  -H "Content-Type: application/json" \
  "https://api.revenuecat.com/v2/projects/projXXXXXXXX/customers/ev_XXXXXXXX/actions/grant_entitlement" \
  -d '{"entitlement_id": "embermarks_cache", "expires_at": 4102444800000}'
```

`expires_at` is required and is milliseconds since the epoch (the value above is
year 2100). To undo it:

```sh
curl -X POST \
  -H "Authorization: Bearer sk_XXXXXXXX" \
  -H "Content-Type: application/json" \
  "https://api.revenuecat.com/v2/projects/projXXXXXXXX/customers/ev_XXXXXXXX/actions/revoke_granted_entitlement"
```

**Important — one claim per entitlement per device.** Each pack is claimed once
(the claim key is the entitlement, deliberately, so a replayed response cannot
grant twice). A granted entitlement therefore *burns* that pack for that device,
and a later real purchase would be deduplicated. So:

- Use a **fresh customer id** for each experiment, or
- Reset the device before recording: uninstall/reinstall the app (clears
  `user://`), which clears both the ledger and `store.cfg`.

For the demo video, do the **purchase first** on a clean install, so the video
shows the purchase delivering the marks rather than "nothing new found".

## Recording the demo

1. Fresh install (`user://` cleared) so the identity and ledger are clean.
2. Open the Glintmonger's Case → tap **GLINT** in the HUD action row.
3. Tap **BUY ONLINE** — the hosted checkout opens in the browser.
4. Pay with the test card.
5. Return to the app → **RESTORE** → marks are delivered.
6. Tap **RESTORE** again to show the idempotency line.
7. Spend some marks on a cosmetic to close the loop.

## Releasing for real

- Replace `EMBERVALE_STORE_FUNNEL_URL` with the **Production** URL.
- Set the App User ID to something durable (an account id) before real
  customers buy, or enable Redemption Links — otherwise a reinstall starts a
  new customer and cannot see the old purchase.
- Re-run the pre-submission gate in `RELEASE_CHECKLIST.md` ("RevenueCat gate").
