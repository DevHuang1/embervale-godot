# Embervale Mobile — Beta 1

**Build date:** 2026-09-07 · **Engine:** Godot 4.7.2 · **ABI:** arm64-v8a-only (Android 7.0+ / minSdk 24; targetSdk 36)
**Package:** `com.devhuang1.embervale` · **App label:** Embervale Mobile
**versionCode:** `1` · **versionName:** `1.0.0`

**Artifact:** `exports/beta1/Embervale-Beta1-arm64-v8a.apk` (124 MB)
**Checksums:** `exports/beta1/SHA256SUMS.txt`
(SHA-256:`020a1f77320a1676de92958129e634ff5c93074800d76c03f4d252704c05813e`)

> Signed with Godot's bundled development certificate — fine for sideloaded testing/distribution via GitHub Releases; **not** for Play Store submission. Store gates are tracked in `../RELEASE_CHECKLIST.md`.

## What is in this beta

- **Golden-route vertical slice** (20–30 min reference route):
  Whispergrove arrival → first readable fight → gathering ritual → forge upgrade →
  Bramblewood expedition → elite lesson → Hushling Matriarch boss (readable
  patterns, guard break, vulnerability windows, phase escalation)→ reward
  choice → Moonfen unlock.
- **Realm visuals**: seven stylized-PBR surface families, five realm terrain profiles
  with distinct palettes, tiered terrain detail (Low/Medium/High quality tiers).
- **Combat feedback**: deterministic sprite VFX with budgets, destruction debris,
  tumble corpses, telegraphs that stay readable under fog at every quality tier.

- **Systems**: quest ledger, satchel/equipment, forge + crafting, shop, camp
  facilities, boss customization, reward choice with idempotent first-clear rewards,
  scan/economy + fragment econ, savable checkpoint recovery along the route.
- **Audio**: procedural synth cues (footsteps, swings, hits, UI, boss lifecycle
  states)and realm ambience beds.

## Install (Android)

1. Attach `exports/beta1/Embervale-Beta1-arm64-v8a.apk` to a **GitHub Release** on
   `DevHuang1/embervale-godot` (Releases → Draft a new release → tag `beta-1` →
   upload the APK → note that GitHub warns about large binaries — attach anyway.**
2. Open the release on your Android phone → download the APK (confirm the size)
   → open it when finished.
3. If asked, allow "Install unknown apps" for the browser/files app you used.
4. Install → launch **Embervale Mobile**.
   No account, no camera, no internet required — fully offline play.

## Verify the download

```sh
shasum -a 256 -c SHA256SUMS.txt
```

## Validated gates (2026-09-07

- `godot --headless --path . --editor --quit` — clean parse (no script errors)
- `tests/test_release_checklist.gd` — **RELEASE CHECKLIST CONTRACT PASSED**
- `tests/test_monetization_safety_audit.gd` — **MONETIZATION SAFETY AUDIT PASSED**
- `tests/test_asset_inventory_audit.gd` — **ASSET INVENTORY AUDIT PASSED**
  (36 gameplay assets;154 review-only)
- `aapt dump badging` + `apksigner verify` on the APK — package/label/version
  confirmed; signature valid (APK Signature Scheme v2, Godot dev cert)

## Known gaps for the next beta

- Release keystore outside the repo (reproducible, private) — needed for store tracks.
-
- Clean-device install/update/uninstall/reinstall + save-migration report (needs a
  physical device run).
- Real-renderer store screenshots at supported aspect ratios.

- Crash logging with privacy-reviewed provider + opt-out.

- RevenueCat purchase/restore/refund validation in a release env (disabled here.
```