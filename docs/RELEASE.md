# Releasing Rubric

Releases run on Codemagic (app `6ac468dff0be487e13eb3bb4`, repo
`SupposedlySam/rubric`), set up like Flyby. One command releases both stores
from an up-to-date, clean `main`:

```bash
tool/release.sh 2.0.3   # *.*.*, the version name users see
```

It tags `main`, pushes the tag (origin pushes to the fork and the original)
and starts the `production-deploy` workflow for that tag through Codemagic's
API, with the token in `.contrib/codemagic/token`. It refuses a dirty tree, a
branch other than `main`, a `main` that differs from origin's, and a version
that is already tagged. `tool/test_release.sh` (run by `tool/check.sh`)
covers each refusal.

**A pushed tag alone does not start a build.** `codemagic.yaml` declares a
`*.*.*` tag trigger, but this app was created in Codemagic's workflow-editor
flow, and no tag push has ever started a build for it; every release from
2.0.0 on was started through the API. If tag pushes start firing one day,
`cancel_previous_builds` stops the duplicate. Check a build's progress with
`python3 .contrib/codemagic/status.py <buildId>`.

The `production-deploy` workflow (`codemagic.yaml`) then:

1. runs `flutter analyze --fatal-infos` and `flutter test` (the same gate as
   `tool/check.sh`);
2. takes the version name from the tag, and the build number from one above
   the highest of Google Play, App Store Connect and `pubspec.yaml`, so no
   store sees a duplicate;
3. builds a signed Android App Bundle and releases it on Play's
   **internal** testing track, where internal testers get it right away;
4. signs iOS automatically (`app-store-connect fetch-signing-files --create`
   makes and reuses Rubric's own distribution certificate) and uploads the
   build to App Store Connect, where internal TestFlight testers get it
   without review;
5. emails supposedlysam@gmail.com with the result.

Submitting to App Review and promoting a Play track stay deliberate,
manual steps, as they are for Flyby.

## Secrets

All of them are in Codemagic as secure variable groups, set through its API,
never in the repo:

| Group | Variables | Source on the dev machine (`.contrib/`, gitignored) |
|---|---|---|
| `android_signing` | `CM_KEYSTORE` (base64), `CM_KEYSTORE_PASSWORD`, `CM_KEY_ALIAS`, `CM_KEY_PASSWORD` | `android/upload-keystore.jks`, `android/keystore.env` |
| `app_store_connect` | `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_KEY_IDENTIFIER`, `APP_STORE_CONNECT_PRIVATE_KEY`, `CERTIFICATE_PRIVATE_KEY` | `appstore/AuthKey_927UAWMVJG.p8` (Admin key "Rubric"), `appstore/cert_private_key.pem`, `appstore/ids.env` |
| `google_play` | `GCLOUD_SERVICE_ACCOUNT_CREDENTIALS` | `play/service-account.json` (`codemagic@rubric-510801`) |

- **Android upload key.** Google Play App Signing holds the real app-signing
  key. If the upload key is lost, ask Google to reset it; nothing is
  stranded. `android/app/build.gradle.kts` reads it from `CM_KEYSTORE_PATH`
  on Codemagic and from `.contrib/android/` locally. Without either, it
  falls back to debug signing and warns loudly.
- **Back these files up** somewhere safe (a password manager). The repo
  can't hold them, and they exist only on this machine and in Codemagic.

## Store identities

- App Store Connect: **Rubric: Grading Made Simple**, Apple ID `6819497920`,
  bundle ID `com.supposedlysam.rubric` (team `SDBBLFN5KU`).
- Google Play: **Rubric: Grading Made Simple**, package
  `com.supposedlysam.rubric`.
- Store screenshots: `tool/store_screenshots.sh` (see the store listing
  test).
