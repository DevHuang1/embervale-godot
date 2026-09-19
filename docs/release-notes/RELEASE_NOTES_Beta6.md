# Embervale Mobile — Beta 6

**Build date:** 2026-09-19 · **Engine:** Godot 4.7.2.stable · **ABI:** arm64-v8a-only (Android 7.0+ / minSdk 24; targetSdk 36)
**Package:** `com.devhuang1.embervale` · **App label:** Embervale Mobile
**versionCode:** `6` · **versionName:** `Beta 6`

**Artifact:** `exports/beta6/Embervale-Beta6-arm64-v8a.apk` (188.9 MB / 198,047,636 bytes)
**Checksums:** `exports/beta6/SHA256SUMS.txt`
(SHA-256: `82322a8d5985ab7cfa0c84afdadff7f687ce0af13e12cb4bbab52a5807c56fb7`)

> Signed with Godot's bundled development certificate — the **same certificate as
> Beta 1–5**, so this installs straight over any earlier beta and keeps existing
> saves. Fine for sideloaded testing/distribution via GitHub Releases; **not** for
> Play Store submission.
>
> **This artifact carries no store configuration and no provider key** — the
> public build has no `store_defaults.tres`, so the shop shows no in-app buy row.
> The keyed Test Store build stays local (`Embervale-Beta6-device-teststore-arm64-v8a.apk`,
> not distributed): write the key with `tools/write_store_defaults.gd` and export
> for device QA, then `--clear` again before any public export. No secret
> (`sk_...`) is ever present in any APK.

## What changed since Beta 5

**Store — native RevenueCat SDK (Android)**

- The Glintmonger's Case sells the three ember-mark packs through the store's own
  purchase sheet: a **BUY** button per pack plus **RESTORE**, using only the
  public SDK key — no secret, no backend, no Stripe.
- Each purchase is re-read from the provider and granted exactly once (keyed by
  transaction id); tapping RESTORE again reports *"No new ownership found"*
  instead of granting twice. Packs are repeatable — two purchases, two grants.
- The browser **BUY ONLINE** row now appears only when a hosted funnel is
  configured, so an SDK-only build never shows a button that can only fail.
- Shipped store values travel as a **resource** (`store_defaults.tres`,
  gitignored) because a plain config file is not packed into an APK. The public
  artifact is exported with no store resource at all; `tools/write_store_defaults.gd`
  writes (or `-- --clear` removes) the file for a local device build.
- Works with a RevenueCat **Test Store** key (simulated purchases, no Play
  account) or a Google Play key; real Play products still need the Play Console.

**Mini-map**

- The realm map is a **player-following window** (~280 m), so the authored route,
  ponds and terrain relief stay readable in the seamless world instead of
  collapsing into the middle of a two-kilometre field.
- Route, water and heightfield relief shading draw under a **discovery fog** that
  clears as you travel and persists per world cell across save/load.
- Markers de-clutter where they pile up, and guidance outside the window clamps to
  the rim so an objective is never simply missing.
- Tapping to expand now grows the map to its full size with a readable legend,
  and the vitals plate yields while it is open.

**Enemies**

- Per-archetype sensing: a frontal **sight cone** with occlusion, close-range
  peripheral awareness, **hearing** that reacts to swings, dodges, footsteps and
  gathering, and a **leash** that turns a kited mob around to walk home instead of
  freezing wherever it was dragged.
- Idle mobs **wander** around their spawn instead of standing still, and turn to
  face what they are fighting.
- Archetype sizes now match their hit, body and attack collision, and attack SFX
  covers every archetype (including the spitter's venom).

**World**

- Boss compounds: each boss haunts a distinct, bounded ruin with a shrine it
  materialises from, a title card, a compound leash, and a retreat when you
  leave. Combat timing, damage, hitboxes and rewards are unchanged.
- Enterable structure interiors, ponds carved into the terrain with conforming
  shores, branched trees in the streamer and grove dressing, and the consolidated
  stylized terrain texture set (duplicate grass/sand/moss/mud variants removed).

## Carried over from Beta 5

- Realm transitions with the streaming loading screen (progress percentage,
  realm-aware tips, no soft-lock fallbacks).
- Contextual interact action across the route loop, stuck-movement fix,
  export-safe content-registry validation.
- The RevenueCat web-funnel path remains available as an optional authority
  (backend proxy or editor/debug direct secret; neither ships with this APK).

## Install (Android)

1. Open the release on your Android phone → download the APK (confirm the size) → open it.
2. If asked, allow "Install unknown apps" for the browser/files app you used.
3. Install → launch **Embervale Mobile**.

Store test: open the Glintmonger's Case (HUD **GLINT**) → **BUY** a pack →
complete the Test Store sheet → the marks arrive → **RESTORE** again to see the
idempotency line.

## Verify

```sh
cd exports/beta6 && shasum -a 256 -c SHA256SUMS.txt
$HOME/Library/Android/sdk/build-tools/36.1.0/aapt2 dump badging \
  exports/beta6/Embervale-Beta6-arm64-v8a.apk | grep -E "package:|minSdkVersion|targetSdkVersion"
```
