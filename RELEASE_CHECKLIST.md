# Embervale release checklist

This is a pre-submission gate. Unchecked items are not claims of completion.
Secrets, signing keys, provider credentials, and production endpoints must be
added only in the release environment.

## Android package and signing

- [x] Confirm package/application ID and display name. (`com.devhuang1.embervale` / "Embervale Mobile" verified via `aapt dump badging` on the Beta 1 APK, 2026-09-07.)
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
- [ ] Validate Android purchase, restore, refund, and entitlement expiration.
- [ ] Grant scans only after provider confirmation and reconcile idempotently.
- [ ] Confirm RevenueCat entitlements never replace the gameplay database.
