# Embervale Mobile — Beta 5

**Build date:** 2026-09-17 · **Engine:** Godot 4.7.2.stable · **ABI:** arm64-v8a-only (Android 7.0+ / minSdk 24; targetSdk 36)
**Package:** `com.devhuang1.embervale` · **App label:** Embervale Mobile
**versionCode:** `5` · **versionName:** `Beta 5`

**Artifact:** `exports/beta5/Embervale-Beta5-arm64-v8a.apk` (185 MB / 194,537,111 bytes)
**Checksums:** `exports/beta5/SHA256SUMS.txt`
(SHA-256: `2fb85f2fc73e801daedec7382bade69b9d5d7468c244fdb1ca5552eddcd24789`)

> Signed with Godot's bundled development certificate — the **same certificate as
> Beta 1–4**, so this installs straight over any earlier beta and keeps existing
> saves. Fine for sideloaded testing/distribution via GitHub Releases; **not** for
> Play Store submission.

**This build supersedes Beta 4** (which is the same feature set without the two
loading-screen wording fixes below). Upload only one of the two to your phone.

## What changed since Beta 4

- The loading screen names the destination: **"Entering Moonfen"** instead of a
  bare "Moonfen".
- The status line follows the load instead of sitting on one word:
  **"Preparing…" → "Streaming terrain…" → "Building the realm…" → "Ready"**.

## What is in this beta (unchanged from Beta 4)

**Realm transitions load behind a loading screen**
- Traveling between realms no longer freezes the frame: the target realm streams
  in on a worker thread while the overlay keeps drawing, and the swap lands in
  one frame once the scene is ready.
- The overlay shows a **progress bar with a percentage at the bottom**, a phase
  status line, the destination title, and a **rotating tip** in the middle that
  fades between entries.
- Tips are **realm-aware**: a travel to Mistfen leads with Mistfen advice, then
  general play tips. Order is deterministic, so repeat visits do not reshuffle
  what you just read.
- Every transition point uses it: realm gates (Bramblewood ⇄ Moonfen), biome
  travel, dungeon select, main menu → game, and quit-to-menu.
- Requests are idempotent: touching a gate twice cannot double-load or strand the
  overlay, a missing scene is refused, and a load that cannot stream falls back
  to a direct load so the player can never soft-lock on the loading screen.

**Carried over from Beta 3**
- Contextual interact action across the route loop: GATHER on resource nodes,
  OPEN on chests, PICK UP on drops, with the HUD naming the live action.
- Stuck-movement fix: a movement key released over an open (paused) menu no
  longer leaves the hero walking on its own.
- Export-safe content-registry validation: packed scenes/scripts resolve through
  the resource loader, so exported builds stop reporting false "missing scene"
  errors while genuinely missing content still fails.
- RevenueCat native bridge (Android, public SDK key only) behind a `NATIVE`
  authority; ledger/idempotent claims unchanged; purchases stay disabled until
  the dashboard has Test Store products and a web purchase link.

## Install (Android)

1. Open the release on your Android phone → download the APK (confirm the size) → open it.
2. If asked, allow "Install unknown apps" for the browser/files app you used.
3. Install → launch **Embervale Mobile**.
   No account, no camera, no internet required — fully offline play.

## Verify the download

```sh
shasum -a 256 -c exports/beta5/SHA256SUMS.txt
```

## Validated gates (2026-09-17)

- `godot --headless --path . --editor --quit` — clean parse (no script errors)
- `tests/test_scene_loader.gd` — **SCENE LOADER TESTS PASSED**, zero script errors
  (monotonic clamped progress, phase status mapping, composed destination titles,
  rotating realm-aware tips, overlay retired and leaves the tree, second travel
  refused, missing scene refused, swap lands on the requested realm)
- `tests/route_end_to_end_validation.gd` — **passes=64 failures=0**
- `tests/test_menu_input_recovery.gd` — **MENU INPUT RECOVERY TESTS PASSED**
- `tests/test_controller_input.gd`, `tests/test_ui_overlap.gd`,
  `tests/test_vfx_ui_smoke.gd` — **PASSED**
- `tests/test_store_security_contract.gd`, `tests/test_revenuecat_native_bridge.gd`
  — **PASSED**
- Real-renderer transition run (1080×1920 portrait): booted Bramblewood, triggered
  the real Moonfen gate path — mid-load overlay at 76% reading "Entering Moonfen"
  / "Building the realm…" with a Moonfen tip, then arrival in `biome=moonfen` with
  the HUD rendering and the overlay retired.
- APK verification: package `com.devhuang1.embervale`, versionName `Beta 5`,
  versionCode `5`, arm64-v8a ABI, signature issued to
  `C=NL, O=Stichting Godot, OU=Godot Engine, CN=Godot` (APK Signature Scheme v2),
  no debug command-line overrides baked in, promo art excluded from the payload.

## Known gaps for the next beta

- Release keystore outside the repo (reproducible, private) — needed for store tracks.
- RevenueCat dashboard still needs Test Store products/entitlements + a web purchase
  link before a real purchase can be tested end to end.
- Clean-device install/update/uninstall/reinstall + save-migration report (needs a
  physical device run).
- Real-renderer store screenshots at supported aspect ratios.
- Android performance profiling on a physical device (emulator GPU cannot represent
  device performance).
