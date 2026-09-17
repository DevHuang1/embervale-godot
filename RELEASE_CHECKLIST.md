# Embervale release checklist

This is a pre-submission gate. Unchecked items are not claims of completion.
Secrets, signing keys, provider credentials, and production endpoints must be
added only in the release environment.

## Android package and signing

- [x] Confirm package/application ID and display name. (`com.devhuang1.embervale` / "Embervale Mobile" verified via `aapt dump badging` on the Beta 1 APK, 2026-09-07; re-verified on the Beta 2 APK via its `AndroidManifest.xml` payload — package `com.devhuang1.embervale`, versionName `Beta 2`, versionCode `2`, engine 4.7.2.stable — 2026-09-08.)
- [ ] Configure release keystore outside the repository and verify reproducible
      export settings.
- [ ] Test install, update, uninstall/reinstall, and save migration on a clean
      Android device.

## Privacy and permissions

- [ ] Request camera permission only when scan UI is opened.
- [ ] Show local-processing/no-upload disclosure before camera capture.
- [ ] Review every manifest permission and remove unused permissions.
- [ ] Verify offline play does not require account or camera access.

## Store and attribution

- [ ] Capture approved real-rendered store screenshots at supported aspect ratios.
- [ ] Include `ASSET_CREDITS.md` and every required pack license in the release.
- [ ] Run asset/license and monetization audits on the release commit.
- [ ] Confirm age rating, parental purchase controls, and refund wording.

## Reliability and support

- [ ] Enable crash logging with a privacy-reviewed provider and test opt-out copy.
- [ ] Test clean save, migration, corrupt-save recovery, suspend/resume,
      low-memory recovery, interrupted scans, and interrupted purchases.
- [ ] Export a support diagnostic and verify it contains no credentials or scan
      images.

## RevenueCat gate

- [ ] Configure RevenueCat only in the release environment.
- [ ] Confirm RevenueCat secret keys never ship in the client: no `sk_` key in
      the repository, the export, or any committed config. The shipping
      authority is the backend proxy; the direct-secret path is editor/debug
      only and refuses release exports.
- [ ] Validate Android purchase, restore, refund, and entitlement expiration.
- [ ] Grant scans only after provider confirmation and reconcile idempotently.
- [ ] Confirm RevenueCat entitlements never replace the gameplay database.
- [ ] Verify the web funnel purchase end to end on a device: buy, return to the
      app, restore, and confirm ember marks land exactly once.
- [ ] Run `tools/verify_revenuecat_setup.gd` against the release project and
      confirm it reports SETUP CHECK PASSED before recording or shipping.
- [ ] Verify a provider grant survives save/load without granting twice.
- [ ] Verify HTTP redirects are refused on every provider request, so the
      Authorization header is never replayed to another host.
- [ ] Confirm a tampered provider ledger row cannot block a legitimate claim.
- [ ] Confirm no secret-shaped value appears in any tracked file
      (`tests/test_store_security_contract.gd` scans the repository).
- [ ] Confirm the Android build enables the `INTERNET` permission and still
      blocks cleartext traffic, and that the support export carries no secret.
- [ ] Re-run `tests/test_revenuecat_entitlements.gd` on the release commit.
