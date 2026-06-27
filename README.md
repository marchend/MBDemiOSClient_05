# AcmeBank iOS

AcmeBank is an iOS 17+ banking app built with Swift 5.10 and SwiftUI,
following an MVVM + Coordinator architecture with Okta OIDC authentication.

## Quick Start

**Prerequisites:** macOS with Xcode 16.0+, Homebrew.

```bash
git clone <repo-url>
cd <repo>
./setup.sh
```

`setup.sh` installs XcodeGen (if missing), generates `AcmeBank.xcodeproj`
from `project.yml`, and opens the project in Xcode.

**Manual fallback** (for environments that block shell scripts):
```bash
brew install xcodegen
xcodegen generate
open AcmeBank.xcodeproj
```

## Running Tests

In Xcode: `Cmd+U` on the `AcmeBank` scheme.

From the terminal (after `xcodegen generate`):
```bash
xcodebuild test -scheme AcmeBank \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO
```

## Okta configuration

The app reads four Okta values at runtime from its `Info.plist`. The
source `AcmeBank/Info.plist` ships sentinel placeholders
(`__OKTA_<KEY>_UNSET__`); the `scripts/inject_okta_config.sh`
postBuildScript replaces them with values from the build process's
environment. Missing env vars are NOT a build error — the sentinels
survive, and `OktaConfig.load()` returns `.notConfigured(reason:)` at
runtime so the app still launches.

| Env var             | Example                                          |
|---------------------|--------------------------------------------------|
| `OKTA_ISSUER`       | `https://example.okta.com/oauth2/default`        |
| `OKTA_CLIENT_ID`    | `0oa1abc2DEF3ghi4JKL5`                           |
| `OKTA_REDIRECT_URI` | `com.acmebank.mobile://callback`                 |
| `OKTA_SCOPES`       | `openid profile offline_access` (space-separated)|

### Three ways to set them

1. **Shell export** (Xcode launched from the same shell — `xed .`):
   ```bash
   export OKTA_ISSUER='https://example.okta.com/oauth2/default'
   export OKTA_CLIENT_ID='0oa1abc2DEF3ghi4JKL5'
   export OKTA_REDIRECT_URI='com.acmebank.mobile://callback'
   export OKTA_SCOPES='openid profile offline_access'
   xed .
   ```
2. **Xcode scheme environment variables**: Product → Scheme → Edit Scheme
   → Run / Test → Arguments → Environment Variables. Add the four
   `OKTA_*` keys. This is the most reliable path because it survives
   Xcode being launched from Finder.
3. **CI secrets**: GitHub Actions exports them into the job env before
   `xcodebuild`. The build script copies them into the built Info.plist.

### `xcodebuild` subshell caveat

`xcodebuild` runs build phases in a clean subshell that does NOT
automatically inherit the calling job's environment. If your CI job
exports `OKTA_ISSUER` at the job level but the `xcodebuild` step doesn't
see it, either:

- pass values inline as build settings:
  ```bash
  xcrun xcodebuild test -scheme AcmeBank \
    -destination 'platform=iOS Simulator,name=iPhone 16' \
    OKTA_ISSUER="$OKTA_ISSUER" \
    OKTA_CLIENT_ID="$OKTA_CLIENT_ID" \
    OKTA_REDIRECT_URI="$OKTA_REDIRECT_URI" \
    OKTA_SCOPES="$OKTA_SCOPES"
  ```
- or set them as scheme environment variables (see option 2 above),
  which `xcodebuild` does read.

## Project Structure

```
AcmeBank/           ← SwiftUI source root (auto-discovered by project.yml globs)
  App/              ← Entry point + root view (ContentView placeholder today)
  Core/Auth/        ← OktaConfig loader (this PR)
  Resources/        ← Asset catalog, entitlements, privacy manifest
  Info.plist        ← Hand-rolled; OKTA_* keys ship as sentinels
AcmeBankTests/      ← XCTest unit tests
AcmeBankUITests/    ← XCUITest end-to-end tests
scripts/            ← Build-phase scripts (inject_okta_config.sh)
project.yml         ← XcodeGen project spec (source of truth for .xcodeproj)
setup.sh            ← Post-clone one-shot setup
```

## Branch Model

| Branch  | Role                       |
|---------|----------------------------|
| develop | Default integration branch |
| qa      | First quality gate         |
| uat     | Pre-prod acceptance        |
| main    | Production / release tags  |

All feature PRs target `develop`. See CLAUDE.md for full conventions.
