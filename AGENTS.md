# AGENTS.md — working agreement for Hermex/Zora

Hermex — since rebranded **Zora** on the home screen; the repo, Xcode target/scheme
(`HermesMobile`), and docs keep the older names — is a native SwiftUI iPhone app for
a self-hosted `hermes-webui` server. `PROJECT_SPEC.md` is the
product/API source of truth — if a request conflicts with it, stop and ask.
Read by every agent (Codex, Claude Code, …); keep it tool-agnostic.

## Session start & wrap-up
- Read `CURRENT.md` first if it exists — it holds the latest resumable state. It is
  local-only (gitignored), never committed; a fresh clone won't have one.
- Read only the `PROJECT_SPEC.md` sections named in CURRENT.md's **Spec Read** field;
  never the whole ~850-line spec unless told to.
- Active work lives in GitHub Issues when available — **issues are currently disabled
  on the fork (`ckorhonen/hermex`), so `gh issue create` fails there**; with no issue,
  use a `chore/` or `fix/` branch and put the scope in the PR body. Implement only the
  issue the human selects, one labeled `ready-for-agent`, or one named in CURRENT.md —
  not every open issue.
- On "wrap up": verify repo/build/test state, then update `CURRENT.md` (it stays
  uncommitted) and commit the code. **Re-read `CURRENT.md` immediately before writing
  it** — concurrent agent sessions share this one file and a blind overwrite has
  clobbered another session's wrap-up before; if it changed since session start,
  merge your state in as a new section instead of replacing the content.
  History lives in `git log` and merged PRs; there is no append-only log.

## How work flows
- One issue → one short `issue/<n>-slug` branch → one PR (branches with no issue use
  `chore/` or `fix/`). Issue/triage/domain conventions live in `docs/agents/`.
- `master` is the protected release-candidate branch: keep it buildable, never do
  feature work on it. **Merging a PR to `master` automatically archives and uploads
  an internal TestFlight build** of the production app via
  `.github/workflows/internal-testflight.yml` — "ship to TestFlight" is usually
  satisfied by the merge itself; don't also archive/upload manually.
- Every PR needs an explicit deploy-impact classification. For app-only/no-deploy-impact
  changes, keep the diff to iOS app/docs/tests, verify any API shape against upstream or
  a running server, and call out in the PR that no server/Worker/signing/App Store Connect
  or infra deploy is required. If that scope changes, say so before pushing/releasing.
- All code/docs changes should go through a PR on the fork remote (`origin`, currently
  `ckorhonen/hermex`) unless the human explicitly says not to. After local validation,
  push the branch, open/update the PR, run an independent autoreview, fix any accepted
  findings, monitor CI, fix CI failures, and iterate until all CI checks and code review
  comments are resolved. You may use subagents/worktrees for review, CI triage, and
  follow-up fixes to save context, but the foreground agent remains responsible for
  verifying diffs, tests, comments, and final status.
- Once the PR is green and all review feedback is resolved, merge it without asking for
  another approval, delete the remote branch when possible, and report the merge SHA.
  Default all GitHub work to the fork remote. Never open an upstream PR, push to
  `upstream`, merge from/to `upstream`, or retarget a PR at the upstream repository
  unless the human explicitly asks for upstream work in that turn. Triage bot/review
  comments before accepting them.

## Hard rules
1. **Never invent API endpoints or JSON shapes.** Read the pinned upstream copy at
   `.codex-tmp/hermes-webui/api/routes.py` (clone it if missing:
   `git clone https://github.com/nesquena/hermes-webui .codex-tmp/hermes-webui`),
   or `curl` your own running server. That upstream copy is read-only — never modify it.
2. **No new third-party dependencies** beyond the spec's locked list without approval.
3. **Tolerant decoding:** every `Codable` model uses optionals for fields upstream
   might add/rename. Never crash on unknown fields.
4. **No destructive commands** (`rm -rf`, `git push --force`, anything touching
   `~/Library/LaunchAgents/` or restarting Mac services). Suggest them; let the human run them.
5. **Don't commit broken builds.** If a build or test fails, fix it before writing more code.

## Tooling
- The maintainer works in **VS Code**, not the Xcode UI — prefer terminal validation;
  ask to open Xcode only when the terminal can't answer.
- Repo-local skills live under `skills/`. When a task matches one, read its
  `SKILL.md` before editing. For device-family, iPad, Mac Designed-for-iPhone/iPad,
  or wide-layout changes, use `skills/ios/hermex-ios-form-factors/SKILL.md`.
- Use **XcodeBuildMCP** for simulator build/test/run/log; fall back to raw
  `xcodebuild`/`xcrun simctl` for release/archive or low-level diagnosis. Defaults live
  in `.xcodebuildmcp/config.yaml` (scheme `HermesMobile`, sim **iPhone 17**); if that
  sim is missing, pick a nearby iPhone and say which.
- **Simulator installs must be signed.** Never install a `CODE_SIGNING_ALLOWED=NO`
  build on the simulator for manual testing — that flag is for compile-only checks
  (see `TESTFLIGHT.md`) and strips entitlements, so Keychain writes fail with
  `errSecMissingEntitlement` and login breaks. Put the app on the sim via XcodeBuildMCP
  `build_run_sim` or a plain signed Debug build (no signing-disabling flags), then install/launch.
- Before asking for review or committing a slice: run the full XCTest suite, and
  build + launch the app for the human's manual simulator test when UI changed.

## App identity (resolved via xcconfig — not grep-able)
Ground truth is `Config/Shared.xcconfig` (+ `Config/BranchTestFlight.xcconfig` for
branch builds); when docs and xcconfig disagree, trust the xcconfig. Currently:
Bundle ID `com.sourcebottle.hermex` · tests `….tests` · Team `CY4LHQ7XSH` ·
display name **Zora** (branch builds: **Zora Branch**).

## "push to branch testflight" (maintainer-only)
Upload the current branch to the side-by-side **Zora Branch** internal TestFlight app
(`com.sourcebottle.hermex.branch`) — a TestFlight upload, **not** a git push.
Requires the maintainer's App Store Connect access; contributors never need this. Use a
unique `CURRENT_PROJECT_VERSION` (e.g. `YYYYMMDDHHMM`) each time. Full commands + branch
identity: `DEVELOPMENT.md`. Never touch the production `com.sourcebottle.hermex` app
unless explicitly asked (remember: merging to `master` already uploads it via CI).

## Working with the human
- Surface tradeoffs in plain English before non-obvious choices; when in doubt, ask.
- Ask before touching anything under the spec's "Open questions."
- After each slice, report: (1) files changed (2) build/test command run (3) result
  (4) next suggested step — plus a short manual simulator test plan when UI changed.

## Keep this file honest
If something here surprises you or contradicts the project, tell the developer and
**propose** an AGENTS.md edit — don't silently edit it. This file is a Band-Aid for what
can't be fixed in code/tests/tooling; your proposed edits are also a signal of what to fix structurally.
