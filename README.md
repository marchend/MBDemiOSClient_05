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

`setup.sh` installs XcodeGen (if missing), writes
`Config/Secrets.local.xcconfig` from any exported `OKTA_*` /
`API_BASE_URL` env vars, generates `AcmeBank.xcodeproj` from
`project.yml`, and opens the project in Xcode.

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

## Runtime configuration (Okta + API_BASE_URL)

The app reads five values at runtime from its `Info.plist` — four Okta
keys and the BFF base URL. They are wired as build-setting references
(`$(OKTA_ISSUER)`, …, `$(API_BASE_URL)`) and Xcode's
`ProcessInfoPlistFile` expands them on every build. The values come
from two xcconfig files:

- `Config/Secrets.example.xcconfig` *(committed)* ships placeholder
  values (`https://placeholder.invalid/oauth2/default`,
  `PLACEHOLDER_CLIENT_ID`, `https://placeholder.invalid`, …) so the
  project builds without any secrets present. When these placeholders
  survive into the built bundle, `OktaConfig.load()` returns
  `.notConfigured(reason:)` (the app launches with the "Okta is not
  configured on this build — see README." banner instead of trying to
  reach `placeholder.invalid`) and `AppConfig.apiBaseURL` rejects the
  placeholder host the same way (Home shows the standard error state
  instead of attempting a real network call).
- `Config/Secrets.local.xcconfig` *(gitignored)* is `#include?`d by the
  example file and overrides those values with real credentials.
  `setup.sh` writes this file from your exported env vars; for CI, the
  same step runs from secrets exposed to the job. Never commit this
  file — `.gitignore` enforces it.

The five env vars below are consumed by `setup.sh` at
project-generation time (they are written into the xcconfig); they do
NOT need to be set in the build/launch environment.

| Env var             | Example                                          |
|---------------------|--------------------------------------------------|
| `OKTA_ISSUER`       | `https://example.okta.com/oauth2/default`        |
| `OKTA_CLIENT_ID`    | `0oa1abc2DEF3ghi4JKL5`                           |
| `OKTA_REDIRECT_URI` | `com.acmebank.mobile://callback`                 |
| `OKTA_SCOPES`       | `openid profile offline_access` (space-separated)|
| `API_BASE_URL`      | `https://bff.dev.acmebank.example.com`           |

### Typical local flow

```bash
export OKTA_ISSUER='https://example.okta.com/oauth2/default'
export OKTA_CLIENT_ID='0oa1abc2DEF3ghi4JKL5'
export OKTA_REDIRECT_URI='com.acmebank.mobile://callback'
export OKTA_SCOPES='openid profile offline_access'
export API_BASE_URL='https://bff.dev.acmebank.example.com'
./setup.sh           # writes Config/Secrets.local.xcconfig, runs xcodegen
```

After merging this PR you must re-run `./setup.sh` (or
`xcodegen generate`) once so the regenerated `AcmeBank.xcodeproj` picks
up the new `configFiles:` wiring.

### xcconfig gotcha: `://` in URLs

A bare `//` in an xcconfig starts an end-of-line comment, so URLs like
`https://example.okta.com/...` must be escaped as
`https:/$()/example.okta.com/...`. `setup.sh` does this automatically;
the committed `Config/Secrets.example.xcconfig` shows the pattern for
hand-edited files.

## Project Structure

```
AcmeBank/           ← SwiftUI source root (auto-discovered by project.yml globs)
  App/              ← Entry point + root view + AppConfig (API_BASE_URL reader)
  Core/Auth/        ← OktaConfig loader, OktaAuthService, KeychainStore
  Features/Home/    ← HomeDashboard model + BFFHomeRepository (GET /v1/home)
  Resources/        ← Asset catalog, entitlements, privacy manifest
  Info.plist        ← Hand-rolled; OKTA_* + API_BASE_URL keys reference $(…) build settings
AcmeBankTests/      ← XCTest unit tests
AcmeBankUITests/    ← XCUITest end-to-end tests
Config/             ← xcconfig files
  Secrets.example.xcconfig   ← committed; placeholder values + #include? of local
  Secrets.local.xcconfig     ← gitignored; written by setup.sh from env vars
scripts/            ← Misc dev/CI scripts (no build-phase scripts)
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
