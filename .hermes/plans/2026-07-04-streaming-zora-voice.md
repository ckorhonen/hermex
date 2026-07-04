# Streaming Zora Voice Implementation Plan

> **For Hermes:** Before execution, run `codewiki_update` for `/Users/ckorhonen/workspace/hermex-zora-branding`; recent status showed the repo registered but `pending_sync: true`. Implement task-by-task with build/test verification.

**Goal:** Add near-real-time spoken Zora replies to Hermex using Chris's existing cloned Zora voice, starting with streaming assistant playback rather than full duplex voice calls.

**Architecture:** Fix and benchmark the local Zora TTS streaming endpoint first. Then add a dedicated iOS streaming PCM playback path using `AVAudioEngine` + `AVAudioPlayerNode`. Keep existing inline audio attachment playback (`InlineAudioPlayerView`) for complete files; do not overload it with streaming behavior.

**Tech Stack:** SwiftUI, AVFoundation, existing Hermes chat streaming, local Zora TTS server (`~/clawd/voice-clone/tts-server-fast2.py`, FastAPI, MLX/Qwen3-TTS), SourceBottle/Zora internal TestFlight pipeline.

---

## Current Findings

### Zora voice server

- Running server observed on `127.0.0.1:11411`.
- Health endpoint reported:
  - `voice: zora`
  - `mode: voice_clone_mlx`
  - `model: mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit`
  - `ref_audio: zora_clean2.wav`
  - `speaker_embed_cached: true`
  - `streaming: true`
  - `streaming_interval: 0.15`
- One-shot endpoint works:
  - `POST /v1/audio/speech`
  - Short sentence timing observed around `3.1s` to first/complete MP3 response.
- Streaming endpoint currently needs repair:
  - `POST /v1/audio/speech/stream` returned HTTP `500`.
  - `POST /v1/audio/speech` with `{ "stream": true }` also returned HTTP `500`.
  - Log evidence pointed at FastAPI/Starlette `StreamingResponse` failing on `ModuleNotFoundError: No module named 'anyio._backends'`.

### Hermex iOS app

Relevant files:

- `HermesMobile/Features/Chat/InlineAudioPlayerView.swift`
  - Complete-file playback via `AVAudioPlayer`.
  - Good for generated/attached MP3/OGG; not appropriate for live PCM chunks.
- `HermesMobile/Features/Chat/TranscriptMediaView.swift`
  - Renders transcript `MEDIA:` audio references via `InlineAudioPlayerView`.
- `HermesMobile/Features/Chat/ChatAttachmentCoordinator.swift`
  - Preserves raw bytes for audio media and downsampled data for image previews.
- `HermesMobile/Features/Chat/ChatViewModel.swift` and chat streaming/API files
  - Likely integration point for deciding when assistant text chunks are stable enough to speak.

### Product recommendation

Build **streaming spoken replies** first, not continuous full-duplex voice.

MVP experience:

1. User sends a normal chat message.
2. Assistant response streams as text.
3. Stable sentence/clause chunks are sent to Zora TTS.
4. Zora audio starts before the full assistant response completes.
5. User can stop/interrupt playback.

---

## Non-goals for v1

- Do not replace existing inline audio attachment playback.
- Do not build always-listening or continuous duplex voice in the first pass.
- Do not route realtime playback through the Hermes command TTS provider; that path buffers complete files.
- Do not add a new third-party dependency without explicit approval.
- Do not switch away from the specific Zora cloned voice unless benchmarking proves local latency is unacceptable.

---

## Task 1: Repair and benchmark Zora TTS streaming

**Objective:** Make `/v1/audio/speech/stream` return valid chunked PCM and measure whether this specific Zora voice is fast enough.

**Files / locations:**

- Inspect/modify if needed: `/Users/ckorhonen/clawd/voice-clone/tts-server-fast2.py`
- Inspect logs: `/Users/ckorhonen/clawd/voice-clone/tts-launchd-err.log`
- Identify launchd service with `launchctl list | grep -iE 'zora|tts'`.

**Steps:**

1. Confirm current failure:
   ```bash
   curl -sS -D /tmp/zora-stream-headers.txt -o /tmp/zora-stream.bin \
     -w 'http=%{http_code} starttransfer=%{time_starttransfer} total=%{time_total} size=%{size_download}\n' \
     -H 'Content-Type: application/json' \
     -d '{"model":"zora","input":"Streaming latency test."}' \
     http://127.0.0.1:11411/v1/audio/speech/stream
   ```

2. Repair the running FastAPI/Starlette streaming runtime:
   - Verify exact Python executable and `sys.path` for the running process.
   - Repair/reinstall `anyio`, `starlette`, `fastapi`, and `uvicorn` for that interpreter if needed.
   - Restart only the Zora TTS service/process after confirming the correct launchd label.

3. Re-test streaming:
   ```bash
   curl -sS -D /tmp/zora-stream-headers.txt -o /tmp/zora-stream.pcm \
     -w 'http=%{http_code} starttransfer=%{time_starttransfer} total=%{time_total} size=%{size_download}\n' \
     -H 'Content-Type: application/json' \
     -d '{"model":"zora","input":"Streaming should begin quickly for this Zora voice test."}' \
     http://127.0.0.1:11411/v1/audio/speech/stream
   file /tmp/zora-stream.pcm
   wc -c /tmp/zora-stream.pcm
   ```

4. Benchmark short, medium, and long text:
   - Record `time_starttransfer`, `time_total`, and byte count.
   - Target: first audio chunk `< 1.0s` preferred; `< 2.0s` acceptable for MVP.
   - If first chunk remains near total generation time, treat server streaming as not useful and use sentence-level one-shot generation queue instead.

---

## Task 2: Add a dedicated iOS streaming audio abstraction

**Objective:** Create a separate streaming playback model for PCM chunks.

**Files:**

- Create: `HermesMobile/Features/Chat/StreamingAudioPlayer.swift`
- Add tests if pure logic is extracted: `HermesMobileTests/StreamingAudioPlayerTests.swift`

**Design:**

Use an observable model owning:

- `AVAudioEngine`
- `AVAudioPlayerNode`
- PCM format from server headers: sample rate, channels, bit depth
- phase state: idle, connecting, playing, paused, finished, failed
- cancellation/stop support

Do not reuse `InlineAudioPlayerView` for streaming; keep that for complete-file attachments.

---

## Task 3: Add a Zora streaming TTS API client

**Objective:** Stream raw PCM chunks from Zora TTS into the iOS playback model.

**Files:**

- Create or modify: `HermesMobile/API/APIClient+TTS.swift`
- Tests: `HermesMobileTests/APIClientTTSTests.swift` using existing URL loading test style.

**Behavior:**

- Endpoint: configurable server base URL + `/v1/audio/speech/stream`.
- Request body:
  ```json
  { "model": "zora", "input": "..." }
  ```
- Response:
  - `audio/pcm`
  - headers: `X-Sample-Rate`, `X-Channels`, `X-Bit-Depth`
- Expose chunks as `AsyncThrowingStream<Data, Error>`.

**Tests:**

1. Encodes expected JSON payload.
2. Accepts `audio/pcm` response and yields chunks in order.
3. Fails gracefully on non-200 response.
4. Cancels the underlying request when playback stops.

---

## Task 4: Add assistant speech chunking

**Objective:** Decide when streamed assistant text is stable enough to speak.

**Files:**

- Create: `HermesMobile/Features/Chat/AssistantSpeechChunker.swift`
- Tests: `HermesMobileTests/AssistantSpeechChunkerTests.swift`

**Rules:**

- Buffer streamed assistant text.
- Emit complete sentences or clauses ending in `.`, `!`, `?`, `:`, or newline after a minimum length.
- Coalesce very short fragments.
- Skip or simplify code fences, markdown tables, and raw URLs for v1.
- Flush remaining text on response completion.

---

## Task 5: Wire spoken replies into chat behind a feature flag

**Objective:** Add opt-in spoken assistant responses without disrupting normal chat.

**Files:**

- Modify: `HermesMobile/Features/Chat/ChatView.swift`
- Modify: `HermesMobile/Features/Chat/ChatViewModel.swift`
- Add setting/toggle in the appropriate settings/chat control surface.

**Behavior:**

- Feature flag: `spokenRepliesEnabled`, default off unless Chris wants it on for internal builds.
- Assistant stream chunks feed `AssistantSpeechChunker`.
- Emitted chunks call the Zora streaming TTS client.
- Playback enqueues streamed PCM chunks.
- New user message, stop tap, or stream cancellation stops TTS and playback.
- UI shows compact state: `Speaking…`, `Stopped`, `Voice unavailable`.

---

## Task 6: Add interrupt / barge-in primitive

**Objective:** Let the user stop current speech immediately.

**Behavior:**

- Stop button cancels:
  - current TTS network request
  - queued audio buffers
  - active `AVAudioPlayerNode`
- Starting a new spoken response stops previous speech.
- Existing inline audio attachment playback and streaming spoken replies should not overlap.

---

## Task 7: Optional tap-to-talk input

**Objective:** Add user speech input only after spoken replies feel good.

**Approach:**

- Use iOS mic capture plus approved ASR path.
- Send transcript into normal Hermes chat flow.
- Keep push-to-talk, not always-listening, for v1 privacy and complexity.
- Defer continuous duplex voice until reply playback is solid.

---

## Validation Plan

### Server validation

- `/health` shows `streaming: true`.
- `/v1/audio/speech/stream` returns HTTP `200` and non-empty PCM.
- First-byte latency recorded for short/medium/long text.
- PCM can be converted/played locally for sanity.

### iOS validation

Run:

```bash
xcodebuild test \
  -project HermesMobile.xcodeproj \
  -scheme HermesMobile \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Manual checks:

1. Normal text chat still streams correctly.
2. Existing `MEDIA:` inline audio still plays complete files.
3. Spoken replies begin before the full assistant response completes.
4. Stop button cuts audio immediately.
5. New user message cancels current spoken response.
6. Zora TTS offline state is non-blocking and visible.

### Release gate

After code lands on `master`, use the established SourceBottle/Zora internal TestFlight flow unless explicitly skipped. Receipt should include:

- Git SHA
- TestFlight build number
- ASC build ID
- processing state
- internal beta state

---

## Risks and Tradeoffs

| Risk | Why it matters | Mitigation |
|---|---|---|
| TTS streaming endpoint currently 500s | App work depends on real chunked PCM | Fix server/runtime first; benchmark before iOS work |
| First chunk may still be slow | If model emits only after full generation, UX will not feel realtime | Fall back to sentence-level one-shot TTS queue |
| AVAudioEngine chunk playback is more complex than AVAudioPlayer | Scheduling/cancellation/format bugs | Build isolated streaming player and test first |
| Full duplex is too much for v1 | Mic, ASR, echo, barge-in, permissions | Ship spoken replies first; tap-to-talk second |
| Voice identity vs latency | Cloned Zora voice may trade speed for quality | Measure; only consider fallback provider if local UX misses target |

---

## Recommendation

Do Phase 1 next:

1. Repair Zora streaming endpoint.
2. Benchmark first-chunk latency.
3. If acceptable, implement the streaming PCM player and TTS client behind a feature flag.
4. If not acceptable, implement sentence-level one-shot TTS queue and defer true streaming.

This preserves the specific Zora voice, avoids premature full-duplex complexity, and gives the app a meaningfully more alive voice experience without rebuilding the whole conversation stack.
