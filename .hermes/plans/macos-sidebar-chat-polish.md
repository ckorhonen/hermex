# Hermex macOS/sidebar/chat polish work order

Goal:
- Implement Chris's eight requested Hermex UI/behavior updates with isolated Spark/Qwen workers, then integrate and verify on the foreground branch.

Repo context:
- Repo: `/Users/ckorhonen/workspace/hermex`
- Mainline: `master` tracks `origin/master`; fork remote `origin` only.
- Rules: `AGENTS.md`; use PR workflow, no direct upstream work, no broken build commits.
- Repo-local skill: `skills/ios/hermex-ios-form-factors/SKILL.md`; UI/layout changes require iPhone/iPad/Mac compile consideration.
- CodeWiki repo is registered but pending sync; use direct file inspection for final decisions.

Requested changes / acceptance criteria:
1. Sidebar ordering: render Automations and Wiki above Active Profile and Projects.
2. Floating `Chat`/New Chat button: white fill with dark text, matching prompt submit button, not theme/glass-tinted.
3. New Chat repeat bug: after clicking Chat/New Chat and starting a conversation, the button works again without first selecting another chat.
4. Session indicators: Live indicator should be robust against stale `/api/sessions` data by reconciling active stream/server status; when a finished chat is unread, show a yellow dot.
5. macOS/wide sidebar header: move `Zora` wordmark plus Search/Account controls into the sidebar header row aligned with the show/hide-sidebar action/titlebar row where SwiftUI exposes a safe toolbar/header placement; preserve iPhone behavior.
6. macOS chat header gradient: start at top of screen and extend through title bar with a linear fade, less harsh than the current solid-plus-knee overlay.
7. Session rows: remove workspace text after message count in the visible list metadata.
8. Chat header: show title only; remove profile subtitle under the title.

Worker split:

## Worker A — sidebar chrome + New Chat behavior
Files expected:
- `HermesMobile/Features/SessionList/SessionListView.swift`
- `HermesMobile/Features/SessionList/SessionListComponents.swift`
- Any focused tests needed under `HermesMobileTests/`

Tasks:
- Move `topLevelUtilityGrid` before `activeProfileHeader` in `SessionSidebarUtilityRows.body`, with clean spacing.
- Make the floating Chat button an explicit white capsule with dark text/icon; do not let theme tint or glass fallback invert it.
- Fix repeat New Chat in split navigation: after a new pending session becomes a real chat, the FAB should no longer remain disabled forever. Preserve the intended guard against double-creating while session creation is in-flight.
- Investigate the macOS/wide header request. If toolbar/titlebar APIs are too broad for a safe slice, implement the safe first step: keep the header controls in the sidebar top chrome row and ensure they align as a single compact header on wide screens; document what remains.

Verification expected:
- `xcodebuild test -project HermesMobile.xcodeproj -scheme HermesMobile -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:HermesMobileTests/<focused-tests>` if tests are added/changed, or an exact blocker.
- `git diff --stat` and summary.

## Worker B — session indicators + chat header/metadata
Files expected:
- `HermesMobile/Features/SessionList/SessionRowView.swift`
- `HermesMobile/Features/SessionList/SessionListView.swift`
- `HermesMobile/Features/SessionList/SessionListViewModel.swift`
- `HermesMobile/Features/Chat/ChatView.swift`
- `HermesMobileTests/SessionIdentityTests.swift`
- `HermesMobileTests/ChatToolbarHeaderTests.swift`
- Any focused tests needed under `HermesMobileTests/`

Tasks:
- Remove visible workspace metadata after message count. Prefer changing the default call site or metadata function so visible rows show message count only. Keep tests aligned.
- Make `ChatToolbarTitleLabel` title-only for header display/accessibility, or pass no subtitle from `ChatView` and delete/retire subtitle resolver tests appropriately.
- Soften `ChatHeaderBackgroundGradient` to a simple top-to-bottom linear fade that covers safe area + inline titlebar/header height, without a hard solid/knee stop.
- Improve session status indicator model:
  - Green dot means server/status says active (`is_streaming` true or non-empty `active_stream_id`).
  - Session-list monitor should not rely only on rows already marked active; periodically poll likely recent sessions or refresh list so active rows discovered only after opening the chat are surfaced.
  - Add yellow unread/finished dot if existing model/server data can support it safely. If no unread server field exists, add a local conservative pending-unread marker only when a previously active row transitions to completed while not selected/open; do not invent API fields.

Verification expected:
- Focused XCTest(s): `SessionIdentityTests`, `ChatToolbarHeaderTests`, and any new status-monitor test.
- `git diff --stat` and summary.

Execution rules for workers:
- Use only the assigned worktree.
- Inspect before editing.
- Do not push, merge, deploy, archive, upload to TestFlight, or message anyone.
- Do not edit `.codex-tmp/hermes-webui`.
- Keep diffs small and scoped. No broad formatting.
- Run real verification or report exact blocker/output.
- Final report schema:
  - Result:
  - Files changed:
  - Verification run, with output:
  - Risks/blockers:
  - Recommended integration notes:

Foreground integration plan:
- Inspect each worker diff directly; accept only scoped changes.
- Create integration branch from latest `origin/master`.
- Apply accepted diffs deliberately, resolve conflicts, run focused tests/build, autoreview, PR, CI, merge when green.
