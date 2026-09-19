# Embervale — Shipaton submission steps

Operator checklist for the Shipaton 2026 submission (Next Gen Award). Deadline:
**September 30, 2026, 11:45 PM PDT**. Ordered by risk: the first three steps are
what actually decide whether this can be submitted.

Placeholders below (`projXXXXXXXX`, `sk_XXXXXXXX`, `ev_XXXXXXXX`,
`https://pay.rev.cat/<link_id>`) stand for your own values. Never paste a real
secret into this file or any other tracked file — the app reads it from the
environment only, and `tests/test_store_security_contract.gd` fails the build if
a secret-shaped value appears anywhere in the repository.

---

## 1. Get the work onto GitHub

The public repository must contain all source, plus a detectable open-source
license file. `LICENSE` (MIT) must be visible at the top of the repository page.

- [ ] Commit the store integration, the license, the docs, and the game state
      they depend on.
- [ ] Push to `main`.
- [ ] Confirm on GitHub that the repository shows **MIT license** in the About
      section (not "No license") and that `docs/REVENUECAT_SETUP.md` opens.

## 2. Create the RevenueCat project

> **SDK-only build (no Stripe):** follow `REVENUECAT_ANDROID_SDK.md` instead of
> the funnel steps below — the three product/entitlement ids are the same, the
> key goes in the shipped defaults resource, and there is no funnel or Stripe
> step (see `REVENUECAT_ANDROID_SDK.md`).

Follow `docs/REVENUECAT_DASHBOARD_RUNBOOK.md`, Path A. Summary:

- [ ] Account → connect Stripe (**sandbox or test mode is enough**).
- [ ] Project → *Web* → create a **RevenueCat Billing** web config.
- [ ] *Product catalog → Products* → create three **non-consumable** products.
- [ ] *Product catalog → Entitlements* → create three entitlements with these
      exact identifiers:
      `embermarks_pouch`, `embermarks_cache`, `embermarks_bloodstone`.
- [ ] Attach each product to its matching entitlement.
- [ ] *Offerings* → one offering containing all three packages → set as default.
- [ ] *Funnels → Purchase Links* → new link using that offering → publish.
- [ ] Copy the **Sandbox** URL (testing/demo) and the **Production** URL (later).

Values to keep:
- project id: `projXXXXXXXX`
- secret key (V2, permission `customer_information:customers:read`): `sk_XXXXXXXX`
- purchase link base: `https://pay.rev.cat/<link_id>`
- customer / App User ID: `ev_XXXXXXXX`
  (the app's own id is in `user://store.cfg` → `customer_id`)
- public SDK key for the native reader: `goog_XXXXXXXX` (safe to ship; goes in
  the gitignored `res://store_defaults.tres` for an APK build, never in a
  committed file)

Before an APK build, write `store_defaults.tres` with
`tools/write_store_defaults.gd` (`project_id` / `funnel_url` / `native_api_key`;
see the dashboard runbook, "Where each value goes"). It is gitignored and only
read by exported builds.

## 3. Prove the chain on desktop first

Desktop is the fastest place to find a dashboard mistake, because environment
variables work there.

- [ ] Run the checker and get `SETUP CHECK PASSED`:

```sh
EMBERVALE_REVENUECAT_PROJECT_ID=projXXXXXXXX \
EMBERVALE_REVENUECAT_SECRET=sk_XXXXXXXX \
EMBERVALE_STORE_CUSTOMER_ID=ev_XXXXXXXX \
EMBERVALE_STORE_FUNNEL_URL=https://pay.rev.cat/<link_id> \
godot --headless --path . --script tools/verify_revenuecat_setup.gd
```

- [ ] Run the game with the same variables, then in-game:
      **GLINT → BUY ONLINE → pay with test card `4242 4242 4242 4242` → RESTORE**.
- [ ] Confirm the message reads *"1 pack delivered · +180 ember marks"*.
- [ ] Tap **RESTORE** again and confirm *"No new ownership found"*.

## 4. Do it on the phone

Android cannot read environment variables, so the build carries its non-secret
values in `res://store_defaults.tres` (gitignored; editor/CI ignore it):

```sh
EMBERVALE_REVENUECAT_PUBLIC_KEY="test_XXXXXXXX"   # or goog_... for Play
godot --headless --path . --script tools/write_store_defaults.gd
# -> STORE DEFAULTS WRITTEN   (-- --clear removes it for a public build)
```

- [ ] Write `store_defaults.tres` for the path you are demoing.
- [ ] Validate it offline: `godot --headless --path . --script tools/verify_revenuecat_setup.gd`
      -> `SHIPPED DEFAULTS VALID`.
- [ ] Export the APK, install on the device.
- [ ] Confirm the manifest carries the `INTERNET` permission
      (`aapt2 dump xmltree --file AndroidManifest.xml app.apk | grep -i internet`).
- [ ] Confirm the install floor: `aapt2 dump badging app.apk | grep -i sdkVersion`
      must report `sdkVersion:'24'` and the expected versionCode.
- [ ] Repeat the purchase + restore on the device (`tests/android_native_store_check.tscn`
      prints the `QA_NATIVE RESULT` verdict for the SDK path).

One claim per entitlement per device: a test grant or a first purchase *burns*
that pack for that device. Use a fresh customer id per experiment, and
**uninstall/reinstall before recording** so the video shows the purchase
delivering marks rather than "nothing new found".

## 5. Submission assets

- [ ] Demo video, **under 2 minutes**, public on YouTube or Vimeo, showing the app
      running: GLINT → BUY ONLINE → test-card checkout → RESTORE → RESTORE again
      (idempotency) → spend marks on a cosmetic.
- [ ] App icon **1024 × 1024**.
- [ ] Screenshot **1179 × 2556**, no device frame.

## 6. Devpost

- [ ] Register and confirm your student email is verified.
- [ ] Fill in the project description, video link, repository link, icon,
      screenshot.
- [ ] Select **Next Gen**. (Add **Best Game** only if you also publish to a
      supported store — that category requires a store link.)

## Do not start these yet

- OneSignal / "Keep Them Coming Back" and Stripe "Funnel Vision" — multi-day
  detours that do not matter if step 3 does not pass.
- A Play Store release for "Best Game" — requires a paid account and review time.

Get steps 1–3 green first.

## Releasing for real (after the hackathon)

- [ ] Swap `EMBERVALE_STORE_FUNNEL_URL` to the **Production** URL.
- [ ] Use a durable App User ID (an account id) before real customers buy, or
      enable Redemption Links, or a reinstall loses access to the purchase.
- [ ] Work through the "RevenueCat gate" section of `RELEASE_CHECKLIST.md`.
