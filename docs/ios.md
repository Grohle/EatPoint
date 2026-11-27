# EatPoint on iOS (parked)

EatPoint ships for Android only for now. The iOS app is **parked**: nothing was
removed, and the project keeps every iOS change made so far, so it can be picked
up again later.

## State of the iOS project

- **Identity**: the bundle id is `io.github.grohle.eatpoint`, the display name is
  "EatPoint" ("EatPoint Dev" for the develop flavour), and the app group is renamed
  to match. The launcher icons (`AppIcon`, including the dark and tinted variants)
  come from `assets/icon/eatpoint_launcher_ios_*_1024.png`.
- **Label scanner**: it uses `google_mlkit_text_recognition` 0.15.x, the line that
  still ships CocoaPods specs. The 1.x line is Swift Package Manager only, and the
  iOS build uses CocoaPods. Both lines require iOS 15.5, which matches `ios/Podfile`.
- **Not verified on iOS**: nothing EatPoint adds has been run on an iPhone or a
  simulator. This covers the points, meals, planner, importer, travel mode,
  household sync, MCP and label scanner features.
- **Still to do before a release**:
  - Regenerate `ios/Podfile.lock` with `pod install`. It is out of date with the
    ML Kit pods.
  - Check the camera and photo-library usage strings in `Info.plist` for the
    label scanner and the menu importer.
  - Check that the MCP server can listen on the local network: iOS asks for
    local-network permission (`NSLocalNetworkUsageDescription`).
  - Set up signing with an Apple developer account.

## CI

The iOS jobs in `.github/workflows/default_workflow.yml` only run when the
repository variable `EATPOINT_IOS` is `true`:

- `ios-podfile-lock-guard`
- `ios-build`
- `ios-integration-tests`
- `ios-integration-tests-retry`
- `ios-integration-tests-result`
- `ios-smoke-alarm`

The original app's store deploy chain (`release-gate` and the jobs that follow
it, which publish to the App Store and Google Play) only runs when
`EATPOINT_STORE_DEPLOY` is `true`. EatPoint has no store listings yet, and its
GitHub releases come from the separate `EatPoint release` workflow.

To work on iOS again, set `EATPOINT_IOS` to `true` in **Settings → Secrets and
variables → Actions → Variables**. Then fix the first `ios-build` run: its
"Auto-commit refreshed iOS project files" step pushes a fresh `Podfile.lock`
to pull-request branches.
