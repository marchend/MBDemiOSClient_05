# CI/CD Security Baseline

> Applied automatically by the **MothershipCode CI/CD Hardener**. Do not
> hand-edit this file — re-run the hardener if the baseline changes.

This repository is configured with the tier-by-branch security pipeline
defined in [MothershipCode 07-cicd-security-pipeline](https://github.com/marchend/AgenticSoftwareDev/blob/main/architecture/07-cicd-security-pipeline.md).

## Branch Model

| Branch | Role | Required CI |
|---|---|---|
| `develop` | Default integration branch — feature PRs land here | `ci.yml` + `ios-build.yml` |
| `qa` | First quality gate | `ci.yml` + `security-fast.yml` |
| `uat` | Pre-prod acceptance | `ci.yml` + `security-deep.yml` + `mobile-security.yml` |
| `main` | Production / release tags | `ci.yml` + `security-deep.yml` + `mobile-security.yml` |

All feature PRs **must** target `develop`. Promotions to
`qa`, `uat`, and `main` happen via
dedicated promotion PRs.

## Detected Stack

- **iOS** — Swift sources
## Workflows

| File | Trigger | What it scans |
|---|---|---|
| `.github/workflows/security-fast.yml` | PR → `qa`, push `qa` | Gitleaks (diff), Semgrep, Trivy |
| `.github/workflows/security-deep.yml` | PR → `uat`/`main`, push, weekly cron, `security:full` label | Gitleaks (full history), Semgrep OWASP rule packs, OWASP Dependency-Check |
| `.github/workflows/mobile-security.yml` | Same as `security-deep.yml` | MobSF static analysis (source-mode, score ≥ 60) |
| `.github/workflows/ios-build.yml` | PR → `develop`, push `develop` | `xcodegen generate` + `xcodebuild build` + `xcodebuild test` (iOS Simulator, no signing). Also captures a launch-screen screenshot via `simctl` and uploads it as the `app-launch-screenshot` artifact for visual review on the PR. |

## Severity Thresholds

| Severity | Fast tier | Deep tier |
|---|---|---|
| CRITICAL | Block | Block + open P0 issue |
| HIGH | Block | Block + open P1 issue |
| MEDIUM | Warn (non-blocking) | Open P2 issue |
| LOW | Report only | Report only |

## Suppressing Findings

- **Trivy CVE suppressions** — add to `.trivyignore` at the repo root with
  an owner + expiry comment. See the file's header for format.
- **Bandit suppressions** — `# nosec B###  reason: ...` inline.
- **Semgrep suppressions** — `# nosemgrep: rule-id  reason: ...` inline.

Avoid blanket suppressions; each entry should explain why and when to
revisit.

## Required Status Checks (post-merge)

The Hardener's "Apply branch protection" follow-up step configures branch
protection to require these contexts:

- `develop` — `ci.yml` jobs only
- `qa` — `ci.yml` + `security-fast.yml`
- `uat` — `ci.yml` + `security-deep.yml` + `mobile-security.yml`- `main` — `ci.yml` + `security-deep.yml` + `mobile-security.yml`