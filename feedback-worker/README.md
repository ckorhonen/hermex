# Zora Feedback Worker

Private feedback intake for the Zora/Hermex iOS shake-to-report flow.

## Public endpoint

- `POST /api/feedback` — accepts user-initiated iOS feedback reports.
- `GET /health` — deployment health check.

The iOS app sends typed notes, app/build metadata, device metadata, current app surface, optional screenshot metadata, and optional rectangle markup.

## Admin endpoint

Requires the admin bearer token in the `Authorization` header. Do not commit or print the token.

- `GET /api/admin/feedback?status=new&app=zora-ios&limit=50` — list queue rows for automation.
- `PATCH /api/admin/feedback` — update status for one or more rows:

```json
{"id":"feedback-id","status":"done","notes":"Released in TestFlight build ..."}
```

Supported statuses: `new`, `planned`, `in_progress`, `done`, `ignored`.

## Cloudflare resources

- Worker: `zora-feedback-inbox`
- URL: `https://zora-feedback-inbox.sourcebottle.workers.dev`
- D1 database: `zora_feedback_inbox`
- D1 binding: `DB`
- Required secret: `ADMIN_TOKEN`

The admin token is stored locally in macOS Keychain under service `zora-feedback-admin-token` for release/cron automation. Do not commit or print it.

## Commands

```bash
npm install
npm run typecheck
npm test
npm run migrate:remote
npm run deploy
```
