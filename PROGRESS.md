# Progress

## Completed

- Collected UI/product requirements and supplied criteria catalog.
- Created a 41-field draft configuration from the 39-field source; original preserved privately.
- Created .env key setup, Git exclusions, synthetic Decisions test, and five passing offline harness tests.
- Verified live Decisions access and Responses structured extraction.
- Identified OpenAI cloud-audio quota failure, power requirement, and public-distribution gaps.
- Replaced ElevenLabs with OpenAI in the plan and advanced the deadline to October 10 at 08:00 Pacific.
- Prepared OVERNIGHT_PLAN.md and PREFLIGHT.md.
- Built the prior native app successfully in 7.88 seconds using a separate temporary build directory.
- Created the independent Swift package, native app target, reusable core, and native CLI probe.
- Implemented dynamic configuration loading/validation/round-trip export, aliases, numeric/enum validation, and call-layout ordering.
- Implemented SQLite persistence for company truth, configuration revisions, calls, transcript revisions, job queue, preferences, and atomic change events.
- Implemented manual-edit locks, proposed replacements, acceptance retaining locks, undo version protection, clear watermarks, source policies/debrief, stale-job rejection, company/config isolation, and distinct collapsed field counts.
- Implemented Keychain credentials and explicit developer .env loading without bundling secrets.
- Implemented parallel Decisions + Responses extraction with canonical-option agreement, exact quote validation in the reducer, quota circuit breaking, no redirect credential forwarding, and a persisted estimated spending ledger.
- Verified 18 Swift tests passing.
- Verified the actual native pipeline with one synthetic excerpt: 4/4 expected fields correct, 3.52 seconds transcript-to-candidates, zero warnings, estimated cost $0.000713.
- Power was subsequently observed as AC Power (battery still discharging at that instant); keep external power connected.

## Current stage

The real native interface now launches and has been exercised through macOS accessibility: manual event name → Start (without Calendar), synthetic transcript → four correct visible values, inline 800→900 manual edit locking automatically, Command-Z restoring 800 and unlocked state. Settings shows masked key entry, Save/Remove, Test text APIs, optional Calendar connection, JSON configurations, appearance, and replay. The provided .env key was explicitly saved to the app's Keychain entry through ScorecardProbe --save-key; no key is bundled.

Core now includes ExtractionSession with independent input arrival, bounded batching, durable queue, per-call identity, copied-state commits, and diagnostics. Transcript+queue+company-watermark persistence is atomic. 21 Swift tests pass, including an in-flight manual-edit race and persistent quota-stop queue.

The first paced full-call attempt stopped after 79/81 arrived sentences: 79/79 processed within five seconds, p95 1.98s, cost $0.05592, two retained pending entries. This is NOT a successful full-call benchmark. Report: test-results/01-owner-story-1791614577/report.json. Failure was a non-OpenAI decoding/validation error; exact cause not yet confirmed because first run only recorded a generic error. Added schema-path errors and replay-only raw response diagnostics (never headers). Invalid typed fields are now skipped with a warning instead of failing the entire response. Twelve high-level-note candidates were rejected because the generated catalog restricted notes to the salesperson; changed that generated default to either speaker and bumped configuration revision to 2.

A second replay is CURRENTLY RUNNING: unified exec session 45678, command .build/debug/ScorecardProbe --replay --call 01-owner-story --interval 3. It sends 127 sentences. Poll this existing session; DO NOT start duplicate replay workers. Raw synthetic response bodies are written under this run's test-results directory for diagnosis. First session 42280 has finished with failure; no longer active.

The app bundle in dist/Live Scorecard 2.app is an ad-hoc debug development build, built before the latest source/config updates. Rebuild before claiming it reflects HEAD. It remains open with Settings visible and the synthetic UI call ended. CUA binding app exists. A screenshot of the main window was blank with sharing exclusion enabled, while accessibility could inspect fields; this is not evidence about actual Google Meet sharing. Calendar Connect was not clicked; account/permission setup remains user-facing and optional.

## Next actions

1. Poll replay 45678 and diagnose any failure from synthetic response files. Create explicit answer-key-to-41-field evaluation mapping; do not count original unmapped fields as automatic passes. Test remaining two long scripts after correcting measured issues.
2. Implement audio capture/transcription adapter using existing ScreenCaptureKit code and OpenAI; no ElevenLabs. Realtime recheck after user added payment still returned rate_limit_exceeded. Text APIs work. Synthetic TTS/STT roundtrip remains untested.
3. Finish numeric derivation, recovery/retry policy, robust configuration switching and Settings editor/thresholds, keyboard focus navigation, and actual UI validation. Current UI permits configuration switching only after call end; user wanted immediate switching if needed, so this is a known gap. Source calls/history are persisted but post-restart job resume isn't yet surfaced in UI.
4. Verify optional Google Calendar connection and permissions with the user; automatic naming is explicitly next-version scope. Manual name + Start already verified.
5. Package release, license/source review, secret scans, test reports, GitHub publication when authenticated, and final artifacts.

## Verification commands

- swift test --disable-sandbox (21 tests passed; module cache envs can point to /tmp/scorecard2-clang and /tmp/scorecard2-swift in sandbox).
- .build/debug/ScorecardProbe --live-sample uses the real OpenAI core with synthetic data; network access required. Do not repeatedly run without a new reason.
- Usage ledger: ignored private-data/api-test-usage.json. Avoid printing credential files.

## External blockers

- OpenAI Realtime initially returned credit_balance_exhausted; user added payment, explicit recheck returned rate_limit_exceeded. Text APIs work.
- Mac detects AC but battery was still falling (26%, discharging, ~43min remaining at 23:48). User warned to check charger/cable; verify improvement.
- No real Google recordings located for live-audio evaluation.
- GitHub release-upload auth and Developer ID/notarization unavailable.
- New-app capture/calendar permissions and actual Meet sharing test pending.
