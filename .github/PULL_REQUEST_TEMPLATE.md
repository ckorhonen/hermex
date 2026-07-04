<!-- Thanks for contributing! Please read CONTRIBUTING.md before opening a PR. -->

## Linked issue

<!-- Every PR should close an issue, e.g. "Fixes #123". If there is no issue yet, open one first. -->

Fixes #

## What changed

<!-- A short, plain-English summary of the change and why it's the right fix. -->

## How it was tested

<!-- e.g. full XCTest suite (command + result), manual simulator steps, screenshots for UI changes. -->

## Deploy impact

<!-- Pick one and explain briefly. For no-deploy-impact PRs, confirm the diff is app/docs/tests only and no server/Worker/signing/App Store Connect/infra changes are required. -->

- [ ] No deploy impact: app/docs/tests only; no backend, Worker, signing, App Store Connect, or infra changes required.
- [ ] Deploy required: describe the target(s), owner, and rollout/rollback notes.

## Checklist

- [ ] The full test suite passes locally (`xcodebuild test -project HermesMobile.xcodeproj -scheme HermesMobile -destination 'platform=iOS Simulator,name=iPhone 17'`)
- [ ] New/changed `Codable` models decode tolerantly (optionals for fields the server might add or rename)
- [ ] No new third-party dependencies (the list in `PROJECT_SPEC.md` is locked)
- [ ] No invented API endpoints or JSON shapes (verified against upstream source or a running server)
- [ ] Deploy impact is classified above
