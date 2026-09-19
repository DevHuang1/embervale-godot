# Embervale Mobile — Beta 2

**Build date:** 2026-09-08 · **Engine:** Godot 4.7.2.stable · **ABI:** arm64-v8a-only (Android 7.0+ / minSdk 24; targetSdk 36)
**Package:** `com.devhuang1.embervale` · **App label:** Embervale Mobile
**versionCode:** `2` · **versionName:** `Beta 2`

**Artifact:** `exports/beta2/Embervale-Beta2-arm64-v8a.apk` (124 MB / 130,258,361 bytes)
**Checksums:** `exports/beta2/SHA256SUMS.txt`
(SHA-256: `20ddf495977080213b2a3537ad44cc119a837754409a0473590f27d12b7a58a9`)

> Signed with Godot's bundled development certificate — fine for sideloaded testing/distribution via GitHub Releases; **not** for Play Store submission. Store gates are tracked in `../RELEASE_CHECKLIST.md`.

## What is in this beta

**Golden route and onboarding**
- Golden-route catalog + tracker, route checkpoints, stage objectives, and a
  vertical-slice scenario/catalog that encode the 20–30 minute reference route:
  Whispergrove onboarding → Bramblewood expedition → gathering → elite fight →
  boss → valuable loot → equipment/crafting upgrade → visible unlock.
- Onboarding teaching contract and landing-page choreography so early minutes
  teach by play (move, interact, first readable fight) instead of modal dumps.
- HUD objective/action-state clarity (which button is live, why, and when).

**Bosses and combat**
- New **Bramblewood Thornwarden** boss plus a combat training target, boss
  lesson catalog, and boss reward catalog feeding the elite → boss → loot chain.
- Hushling Matriarch lifecycle/phase-transition hardening: readable patterns,
  guard break, vulnerability windows, phase escalation, reliable reset.
- Weapon catalog + visual registry (distinct weapon identities), skill icon
  kinds/performance contract, enemy visual registry, and hit-timing coverage.

**Realm identity**
- Realm identity catalog and modular realm kit: each realm now has composable
  identity pieces (enemies, resources, ambience, landmarks) rather than palettes
  alone; realm expansion + environment story catalogs drive landmarks and
  discovery.
- Terrain relief layers, grass coverage ranges, weather profiles, and world
  chunk streaming to keep exploration readable on mobile tiers.

**Loop, rewards, and economy**
- Reward reveal model + panel with choice wiring and reward history;
  quest rewards are idempotent across death/reload/realm travel.
- Loadout presets, player stat projection, upgrade/action clarity, and item
  comparison in shop/satchel; scan fragments + scan economy + scan pack products.
- Quiz manager/menu, camp progression, shop browse controls, equip-forge flow
  (forge menu) with clearly explained costs.

**Accessibility and mobile UX**
- Settings responsiveness: reduced motion, shake/flash intensity, text scaling,
  target switching, joystick input bindings — all wired through UI tokens and
  gamepad/touch paths.
- Minimap marker categories, UI theme tokens, HUD/action state, responsive
  stats/satchel layouts.

**Systems and validation**
- 222 test scripts shipped in-tree (≈140 new since Beta 1), including release
  checklist contract, monetization safety audit, asset inventory/license audit,
  streaming/asset budget catalogs, time-scale guard, and low-memory recovery.
- Backend reference services (account/session, entitlement, purchase sync,
  cloud sync queue, content manifest, RevenueCat-style webhooks) — staged for
  release-environment use only; the Android app remains fully offline-playable
  with no account, camera, or internet.

## Install (Android)

1. Attach `exports/beta2/Embervale-Beta2-arm64-v8a.apk` to a **GitHub Release** on
   `DevHuang1/embervale-godot` (Releases → Draft a new release → tag `beta-2` →
   upload the APK → GitHub warns about large binaries — attach anyway).
2. Open the release on your Android phone → download the APK (confirm the size)
   → open it when finished.
3. If asked, allow "Install unknown apps" for the browser/files app you used.
4. Install → launch **Embervale Mobile**.
   No account, no camera, no internet required — fully offline play.

## Verify the download

```sh
shasum -a 256 -c exports/beta2/SHA256SUMS.txt
```

## Validated gates (2026-09-08)

- `godot --headless --path . --editor --quit` — clean parse (no script errors)
- `tests/test_release_checklist.gd` — **RELEASE CHECKLIST CONTRACT PASSED**
- `tests/test_monetization_safety_audit.gd` — **MONETIZATION SAFETY AUDIT PASSED**
- `tests/test_asset_inventory_audit.gd` — **ASSET INVENTORY AUDIT PASSED**
- APK verification: `unzip -t` clean; `AndroidManifest.xml` payload confirms
  package `com.devhuang1.embervale`, versionName `Beta 2`, versionCode `2`,
  engine 4.7.2.stable, arm64-v8a ABI; signature block present and issued to
  `C=NL, O=Stichting Godot, OU=Godot Engine, CN=Godot` (APK Signature Scheme v2).

## Known gaps for the next beta

- Release keystore outside the repo (reproducible, private) — needed for store tracks.
- Clean-device install/update/uninstall/reinstall + save-migration report (needs a
  physical device run).
- Real-renderer store screenshots at supported aspect ratios.
- Crash logging with privacy-reviewed provider + opt-out.
- RevenueCat purchase/restore/refund validation in a release env (disabled here).