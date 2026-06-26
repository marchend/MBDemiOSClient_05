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

## Project Structure

```
AcmeBank/           ← SwiftUI source root (auto-discovered by project.yml globs)
  App/              ← Entry point + root view (ContentView placeholder today)
  Resources/        ← Asset catalog, entitlements, privacy manifest
AcmeBankTests/      ← XCTest unit tests
AcmeBankUITests/    ← XCUITest end-to-end tests
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
