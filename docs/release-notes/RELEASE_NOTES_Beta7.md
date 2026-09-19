# Embervale Mobile — Beta 7

**Build date:** 2026-09-19 · **Engine:** Godot 4.7.2.stable · **ABI:** arm64-v8a-only (Android 7.0+ / minSdk 24; targetSdk 36)
**Package:** `com.devhuang1.embervale` · **App label:** Embervale Mobile
**versionCode:** `7` · **versionName:** `Beta 7`

**Artifact:** `exports/beta7/Embervale-Beta7-arm64-v8a.apk` (181.6 MB / 190,405,599 bytes)
**Checksums:** `exports/beta7/SHA256SUMS.txt`
(SHA-256: `c3fc573eff147b006a1ddc01461ef64c2d5e00df6e0473e50d1988b3368909a8`)

> Signed with Godot's bundled development certificate — the **same certificate as
> Beta 1–6**, so this installs straight over any earlier beta and keeps existing
> saves. Fine for sideloaded testing/distribution via GitHub Releases; **not** for
> Play Store submission.
>
> **This build carries a RevenueCat Test Store public key** so the shop's **BUY**
> row works without a Play account and purchases are **simulated** — for demo and
> QA only. The key ships **sealed** (`native_api_key_sealed`, AES-256-CBC under a
> marker), so a literal copy-paste out of the APK does not hand out a working key.
> Sealing is obfuscation, not confidentiality: the passphrase is compiled into the
> same client. No secret (`sk_...`) is present in any APK. Run
> `tools/write_store_defaults.gd -- --clear` before a build that must carry no
> store configuration at all.

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

- The shipped public SDK key is now **sealed in the build resource**
  (`tools/write_store_defaults.gd` seals by default, `--no-seal` opts out), the
  store resolves it before the usual validation, and an unrecoverable blob fails
  closed instead of leaving a stale key configured. `--from-resource` recovers
  values from a previous resource when rotating a key.
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
3. Install → launch **Embervale Mobile**.

Store test: open the Glintmonger's Case (HUD **GLINT**) → **BUY** a pack →
complete the Test Store sheet → the marks arrive → **RESTORE** again to see the
idempotency line.

## Verify

```sh
cd exports/beta7 && shasum -a 256 -c SHA256SUMS.txt
$HOME/Library/Android/sdk/build-tools/36.1.0/aapt2 dump badging \
  exports/beta7/Embervale-Beta7-arm64-v8a.apk | grep -E "package:|minSdkVersion|targetSdkVersion"
```
