# Embervale — Beta 9

**Build date:** 2026-09-19 · **Engine:** Godot 4.7.2.stable · **ABI:** arm64-v8a-only (Android 7.0+ / minSdk 24; targetSdk 36)
**Package:** `com.devhuang1.embervale` · **App label:** Embervale
**versionCode:** `9` · **versionName:** `Beta 9`

**Artifact:** `exports/beta9/Embervale-Beta9-arm64-v8a.apk` (182.5 MB / 191,370,434 bytes)
**Checksums:** `exports/beta9/SHA256SUMS.txt`
(SHA-256: `54022a243e17e6fb0a382deb0d7c781817575628eb5ee9dd2812c35e087feff9`)

> Signed with Godot's bundled development certificate — the **same certificate as
> Beta 1–8**, so this installs straight over any earlier beta and keeps existing
> saves. Fine for sideloaded testing/distribution via GitHub Releases; **not** for
> Play Store submission.
>
> **This artifact carries no store configuration and no provider key**, so the
> shop shows no in-app BUY row on this build. The store path (RevenueCat funnel +
> Stripe sandbox + the `backend/` proxy) runs in a **private QA build**: a public
> artifact must not ship a sandbox purchase link, because anyone holding it can
> "buy" with a Stripe test card. No secret (`sk_...`) is present in any APK.

## What changed since Beta 8

**One menu at a time**

- Opening an overlay while another was up stacked two sheets, and closing the top
  one left the other behind. The HUD sits below the menu layers, but a sheet
  whose dimmer ignores input (the satchel's does) still left the HUD buttons
  reachable, so a second menu really could open on top of the first.
- Every overlay entry point now retires the others first — satchel, shop, Glint,
  settings, stats and the chapter lesson — and the satchel's toggle closes what
  it opened instead of blind-flipping visibility. `tests/test_menu_overlay_exclusion.gd`
  drives the real grove to keep it that way.

**A web purchase arrives when you come back**

- A hosted checkout finishes in the browser, so the purchase landed while the
  game was backgrounded — previously the only way to collect it was to find
  RESTORE in the shop. The game now re-checks the provider on the first frame
  back, but only when a checkout was actually opened, and that one return
  consumes the check. RESTORE remains as the manual re-read.
- This path also needed a transaction read to exist at all: repeatable packs are
  granted once per purchase, so the backend proxy gained
  `GET /transactions?customer_id=…` (see the runbook). Without it a completed
  checkout granted nothing.

**A quest tracker you can fold, and a joystick that actually grows**

- The left-side quest ledger now folds to a single line: tap the chevron in its
  header and the tracker collapses to the current objective (chapter stays in
  the tooltip), freeing the whole left column. The folded state persists across
  sessions, and the strip still names the next step while it is closed.
- The joystick size setting used to scale the stick from its top-left corner, so
  a bigger stick slid off the bottom edge and a smaller one pulled away from the
  thumb corner. It now scales from the corner it is anchored to and grows into
  the space the folded tracker frees; the field-guide line yields to the larger
  stick instead of being overlapped by it.
- Regression coverage: `tests/test_ui_overlap.gd` re-audits the real HUD with
  the ledger folded, and `tests/test_hud_compact_actions.gd` round-trips the
  folded preference and asserts the enlarged stick keeps its bottom anchor.
  Real-renderer evidence: `tools/capture_ui_portrait.gd` writes
  `hud_quest_ledger_expanded/folded` and `hud_joystick_large_folded` captures.

## Install (Android)

1. Open the release on your Android phone → download the APK (confirm the size) → open it.
2. If asked, allow "Install unknown apps" for the browser/files app you used.
3. Install → the launcher shows the **Embervale** flame icon → launch **Embervale**.

## Verify

```sh
shasum -a 256 -c SHA256SUMS.txt
$HOME/Library/Android/sdk/build-tools/36.1.0/aapt2 dump badging \
  Embervale-Beta9-arm64-v8a.apk | grep -E "package:|minSdkVersion|targetSdkVersion|application-label:"
```
