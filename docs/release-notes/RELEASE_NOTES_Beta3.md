# Embervale Mobile — Beta 3

**Build date:** 2026-09-17 · **Engine:** Godot 4.7.2.stable · **ABI:** arm64-v8a-only (Android 7.0+ / minSdk 24; targetSdk 36)
**Package:** `com.devhuang1.embervale` · **App label:** Embervale Mobile
**versionCode:** `3` · **versionName:** `Beta 3`

**Artifact:** `exports/beta3/Embervale-Beta3-arm64-v8a.apk` (211 MB / 211,457,269 bytes)
**Checksums:** `exports/beta3/SHA256SUMS.txt`
(SHA-256: `b33dd5aa84d804e88d8bdb8e2193ff4ed539d8535eeeed9ca6e350a399ae8579`)

> Signed with Godot's bundled development certificate — the **same certificate as
> Beta 1/Beta 2**, so this installs straight over Beta 2 and keeps existing saves.
> Fine for sideloaded testing/distribution via GitHub Releases; **not** for Play
> Store submission. Store gates are tracked in `../RELEASE_CHECKLIST.md`.

## What is in this beta

**Interact action on the route**
- A single contextual interact action now drives the whole Whispergrove → Bramblewood
  loop: **GATHER** on resource nodes, **OPEN** on chests, **PICK UP** on dropped loot,
  with the HUD naming the live action and why it is live.
- Gathering nodes, chest nodes, and loot drops each own their interact prompt and
  reward hand-off; the route validation exercises gather → chest → pickup end to end.

**Input fixes**
- **Stuck movement fixed.** Holding a movement key, opening a menu (which freezes the
  world), releasing the key, then closing the menu used to leave the hero walking in
  that direction on its own. The input manager now keeps observing while the world is
  frozen and rebuilds held state from the engine on resume, so no release can be lost.
- Gameplay actions still stay silent while a menu owns the world (no attacks, dodges,
  or interact triggers firing behind a menu).

**Content validation on device**
- The startup content-registry check no longer reports false "missing scene" errors in
  exported builds: packed scenes/scripts are remapped (`.tscn` → `.scn`), which the old
  file-existence check could not see. Authored references are now resolved through the
  resource loader, so genuinely missing content still fails while packed content passes.

**Store (Android, staged)**
- RevenueCat **native bridge** (Godot Android plugin v2 wrapping `purchases-android`):
  the app can read active entitlements from the device SDK with a public SDK key only —
  no secret ever ships on device.
- `StoreManager` gained a `NATIVE` authority (precedence BACKEND → NATIVE → DIRECT) and
  the existing ledger/idempotent claim path is unchanged, so a claimed entitlement is
  still granted exactly once.
- Public-key validation (`appl_`/`goog_`/`amzn_`/`test_`/`rcb_`) plus sanitized config
  loading; a secret key pasted as a public key is refused, and tampered config is dropped.
- Purchases remain **disabled** until the RevenueCat dashboard has Test Store products
  and a web purchase link; the shop keeps working through the existing web/direct path.

**Validation**
- New headless suites: `tests/test_menu_input_recovery.gd` (the drift regression above)
  and `tests/test_revenuecat_native_bridge.gd` (native bridge contract with an injected
  fake), plus an Android QA scene (`tests/android_native_store_check.tscn`) that prints a
  verdict from a real device run.

## Install (Android)

1. Open the release on your Android phone → download the APK (confirm the size) → open it.
2. If asked, allow "Install unknown apps" for the browser/files app you used.
3. Install → launch **Embervale Mobile**.
   No account, no camera, no internet required — fully offline play.

## Verify the download

```sh
shasum -a 256 -c exports/beta3/SHA256SUMS.txt
```

## Validated gates (2026-09-17)

- `godot --headless --path . --editor --quit` — clean parse (no script errors)
- `tests/test_menu_input_recovery.gd` — **MENU INPUT RECOVERY TESTS PASSED**
  (fails without the fix, with the reported `(0.0, -1.0)` stuck-forward drift)
- `tests/test_revenuecat_native_bridge.gd` — **REVENUECAT NATIVE BRIDGE TESTS PASSED**
- `tests/test_store_security_contract.gd` — **STORE SECURITY CONTRACT PASSED**
- `tests/test_content_registry_adapter.gd` — **ALL CONTENT REGISTRY ADAPTER TESTS PASSED**
- `tests/route_end_to_end_validation.gd` — **passes=64 failures=0**
- `tests/test_vfx_ui_smoke.gd`, `tests/test_ui_overlap.gd` — **PASSED**
- Device run (Android 14 emulator, headless): RevenueCat plugin registers, SDK configures
  with the app user id, Test Store key accepted.
- APK verification: package `com.devhuang1.embervale`, versionName `Beta 3`,
  versionCode `3`, arm64-v8a ABI, signature issued to
  `C=NL, O=Stichting Godot, OU=Godot Engine, CN=Godot` (APK Signature Scheme v2),
  no debug command-line overrides baked in.

## Known gaps for the next beta

- Release keystore outside the repo (reproducible, private) — needed for store tracks.
- RevenueCat dashboard still needs Test Store products/entitlements + a web purchase
  link before a real purchase can be tested end to end.
- Realm-transition loading screen (progress bar + tips) — in progress for Beta 4.
- Clean-device install/update/uninstall/reinstall + save-migration report (needs a
  physical device run).
- Real-renderer store screenshots at supported aspect ratios.
