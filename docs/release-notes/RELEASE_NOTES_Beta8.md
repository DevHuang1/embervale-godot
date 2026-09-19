# Embervale — Beta 8

**Build date:** 2026-09-19 · **Engine:** Godot 4.7.2.stable · **ABI:** arm64-v8a-only (Android 7.0+ / minSdk 24; targetSdk 36)
**Package:** `com.devhuang1.embervale` · **App label:** Embervale
**versionCode:** `8` · **versionName:** `Beta 8`

**Artifact:** `exports/beta8/Embervale-Beta8-arm64-v8a.apk` (182.5 MB / 191,359,981 bytes)
**Checksums:** `exports/beta8/SHA256SUMS.txt`
(SHA-256: `29a8eaa7764b21002f98e467536a85d6cf546620e99bb78afff7128c76fb1df8`)

> Signed with Godot's bundled development certificate — the **same certificate as
> Beta 1–7**, so this installs straight over any earlier beta and keeps existing
> saves. Fine for sideloaded testing/distribution via GitHub Releases; **not** for
> Play Store submission.
>
> **This artifact carries no store configuration and no provider key**, so the
> shop shows no in-app BUY row. Purchases on a Play-less distribution run through
> the web-funnel path (RevenueCat funnel + Stripe sandbox + the `backend/`
> proxy), which stays a **private QA build**: a public artifact must not ship a
> sandbox purchase link, because anyone holding it can "buy" with a Stripe test
> card. No secret (`sk_...`) is present in any APK.

## What changed since Beta 7

**Store plumbing for Play-less purchases**

- A funnel purchase could complete and grant nothing. Repeatable packs are
  consumables, so the claim ledger grants them **once per store transaction** —
  and an entitlement stays active forever after the first buy, so the
  entitlement read cannot tell a second purchase from the first. The backend
  proxy exposed only `/entitlements/active`, and the client reported
  transactions as `unsupported`, so the claim path never ran.
- `GET /transactions?customer_id=...` now maps RevenueCat's `non_subscriptions`
  page to `{product_id, transaction_id, purchased_at}` (milliseconds, `0` when
  the provider gives no date), behind the same constant-time app-token check and
  customer-id guard as the entitlement route. The client reads it with the same
  bearer token and parses it with the existing transaction parser.
- `StoreDefaults` gained an `access_token` field — a rotatable client
  credential, not a provider secret — applied only when it is a safe header
  value. A tampered value clears any earlier token instead of failing open.
- `backend/render.yaml` gained `STORE_APP_TOKEN`; the runbook documents the
  Render deploy (Blueprint path `backend/render.yaml`, or a manual Web Service),
  the value map, and the rule that repeatable packs are **consumables**. The
  earlier "non-consumable" line was wrong: a non-consumable is once-per-customer
  and refuses every later purchase.
- `TERMS.md` adds the publicly hosted terms page RevenueCat Billing requires for
  the checkout footer.

**Also in this release**

- `pytest.ini` makes the backend suite runnable with one command from the
  repository root: the API tests need `backend` on the path, and the security
  contract tests read repo-root-relative paths, so only the root satisfies both.

## Install (Android)

1. Open the release on your Android phone → download the APK (confirm the size) → open it.
2. If asked, allow "Install unknown apps" for the browser/files app you used.
3. Install → the launcher shows the **Embervale** flame icon → launch **Embervale**.

## Verify

```sh
cd exports/beta8 && shasum -a 256 -c SHA256SUMS.txt
$HOME/Library/Android/sdk/build-tools/36.1.0/aapt2 dump badging \
  exports/beta8/Embervale-Beta8-arm64-v8a.apk | grep -E "package:|minSdkVersion|targetSdkVersion|application-label:"
```
