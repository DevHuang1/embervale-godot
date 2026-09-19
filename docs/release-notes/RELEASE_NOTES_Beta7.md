# Embervale Mobile — Beta 7

**Build date:** 2026-09-19 · **Engine:** Godot 4.7.2.stable · **ABI:** arm64-v8a-only (Android 7.0+ / minSdk 24; targetSdk 36)
**Package:** `com.devhuang1.embervale` · **App label:** Embervale
**versionCode:** `7` · **versionName:** `Beta 7`

**Artifact:** `exports/beta7/Embervale-Beta7-arm64-v8a.apk` (182.5 MB / 191,356,205 bytes)
**Checksums:** `exports/beta7/SHA256SUMS.txt`
(SHA-256: `4b6bb1f9ba3e2ed4196c15897aabb3ac43bd8c87aa38f2964189930b3e15fc73`)

> Signed with Godot's bundled development certificate — the **same certificate as
> Beta 1–6**, so this installs straight over any earlier beta and keeps existing
> saves. Fine for sideloaded testing/distribution via GitHub Releases; **not** for
> Play Store submission.
>
> **This build carries no store configuration and no provider key**, so the app
> launches everywhere. A `test_...` key in a release build makes the RevenueCat
> SDK show *"Wrong API key"* and close the app (the first Beta 7 upload did
> exactly that); a `goog_...` key can only complete purchases for installs that
> came from Google Play, which a sideloaded APK is not. Play-less purchasing is
> the web-funnel path, which needs the backend proxy rather than a client key.
> The shop therefore shows no in-app BUY row here; RESTORE and the rest of the
> game are unaffected, and no secret (`sk_...`) is present in any APK. Keyed
> builds are local QA artifacts: `tools/write_store_defaults.gd` writes them and
> `--clear` removes them before a public export.

## App identity

- The APK now ships a real **Embervale app icon** — an ember flame inside a
  copper vale-ring on the dark vale field — as a full adaptive icon
  (background + safe-zone foreground + Android 13 **monochrome** themed layer),
  a legacy launcher icon for API 24–25, the project icon, and the boot /
  Android 12 splash mark. **No Godot logo remains anywhere in the install.**
- The launcher label is now **Embervale** (was "Embervale Mobile").
- The family is generated deterministically — no imported art — by
  `tools/generate_app_icon.gd`, and `tests/test_app_icon_assets.gd` guards exact
  sizes, opaque plates, transparent corners, the 66dp adaptive safe zone, a pure
  white monochrome layer, and the project/preset wiring. Regenerate with:
  `godot --headless --path . --script tools/generate_app_icon.gd`

## What changed since Beta 6

**Terrain material zones and waterline beaches**

- The ground no longer reads as one green wash. A world-scale two-octave field
  carves **coherent sand, dirt and grass regions** with feathered edges, and the
  sand layer is tinted by the realm palette, so Whispergrove, Mistfen, Heartwood
  and Moonfen keep visibly different ground.
- Wherever the river or a pond meets land the surface lays a **beach band**: sand
  runs complete underneath the water plane (bound from `WorldWaterways`) and
  fades into grass over a couple of metres of bank, on the desktop and the
  four-sampler mobile shader alike.
- The old per-channel texture lift was replaced with a luminance-only contrast
  lift, which had been crushing sand to orange and grass to near-black.

**Store**

- A shipped public SDK key is now **sealed in the build resource** when one is
  written (`tools/write_store_defaults.gd` seals by default, `--no-seal` opts
  out), the store resolves it before the usual validation, and an unrecoverable
  blob fails closed instead of leaving a stale key configured.
  `--from-resource` recovers values from a previous resource when rotating a
  key. **The public Beta 7 artifact ships with no store configuration at all**
  (written with `--clear`, verified absent from the APK): keyed builds are local
  device-QA artifacts, because a release build with a `test_...` key is closed
  by the RevenueCat SDK, and only Play-installed builds can complete a `goog_...`
  purchase.
- The store security contract and the native-bridge suite cover the seal:
  round-trip, tamper refusal, plaintext fallback for dev fixtures, and the
  fail-closed shipped path.

**Also in this release**

- Pending route work landed with this build: discovery codex and director, armor
  prop mounting through the visual registry, the boss HUD range fixes, the
  player-following camera work, and the test suites that cover them (armor
  visuals, portrait fit, weapon model scale, legacy weapon names, early forge
  route, quest objective seeding, world waterways).

## Install (Android)

1. Open the release on your Android phone → download the APK (confirm the size) → open it.
2. If asked, allow "Install unknown apps" for the browser/files app you used.
3. Install → the launcher shows the **Embervale** flame icon → launch **Embervale**.

Store: this public artifact has no store authority configured, so the
Glintmonger's Case (HUD **GLINT**) shows no in-app BUY row. Purchases on a
Play-less distribution use the web-funnel path (RevenueCat funnel + Stripe
sandbox + the `backend/` proxy) in a private QA build; the funnel URL is never
published, because anyone holding a sandbox link can "buy" with a test card.

## Verify

```sh
cd exports/beta7 && shasum -a 256 -c SHA256SUMS.txt
$HOME/Library/Android/sdk/build-tools/36.1.0/aapt2 dump badging \
  exports/beta7/Embervale-Beta7-arm64-v8a.apk | grep -E "package:|minSdkVersion|targetSdkVersion"
```
