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

## Current stage (00:12 Pacific)

The native UI and core are implemented and build. Verified through macOS accessibility: manual event name → Start without Calendar, synthetic transcript → four correct visible values, inline edit auto-lock, Command-Z restoring prior value and lock. Settings offers masked key entry/Keychain, API test, optional Calendar, configurations and replay. The app bundle is stale (built before audio integration/latest changes); rebuild before delivery.

Added separate microphone/selected-browser capture using ScreenCaptureKit, bounded per-channel input streams, PCM conversion, client-side voice turn boundaries, OpenAI WebSocket transcription, stable item IDs across out-of-order completions, final transcript ingestion, explicit Apple Speech option, and Settings provider/browser controls. No ElevenLabs or local LLM inference. Audio starts only after explicit Start; replay does not capture. Capture is restricted to the chosen browser rather than all applications. Known gaps: automatic bounded reconnect is not yet implemented (explicit reconnect works in code), real ScreenCaptureKit/Google Meet capture and permissions are untested, and final audio-drain/reconnect lifecycle needs additional testing.

**OpenAI AUDIO ACCESS IS NOW VERIFIED.** At ~00:07 the new adapter transcribed a generated 7.58-second Samantha speech file, then passed software=Drake Desktop, employee_count=6, number_of_returns=800 through the real core pipeline. Transcript: test-results/audio/transcribed.txt. Source audio and PCM under test-results/audio. This is a short synthetic roundtrip, not live Meet/audio-to-screen latency proof. Reserved $0.034 conservatively in the shared test ledger. The earlier quota/rate-limit blocker no longer applies to this tested request.

27 Swift tests pass, including audio silence/chunking/last-voice timestamp, out-of-order commit identity, concurrent manual-edit protection, and two production-response regression cases. Five Python harness tests also previously passed.

## Replay findings and current worker

First long call completed through recovery, not an uninterrupted run. Full 127 sentences are persisted with zero pending in test-results/01-owner-story-1791615393. It took two parser fixes: (1) model returned several values for one software field; use the Decisions-supported primary and skip extras rather than aborting; (2) API returned the same complete JSON twice in separate output_text items; deduplicate identical documents rather than concatenating invalid JSON. Conflicting documents remain rejected. Regression tests cover both. The first earlier run at test-results/01-owner-story-1791614577 remains an incomplete baseline.

Evaluation using scripts/evaluate-replay.py gives 12/13 explicitly mapped core checks for completed call 1; five additional populated fields require manual review. The failure: number_of_returns became 240 (proposed purchase volume) instead of actual annual firm volume 684. Strengthened definitions for annual volume, overlapping team roles, monetary fields, and hosting provider. Catalog revision is now 3. Do not claim accuracy or latency targets passed; resumed-call latency includes real recovery delay, and the key volume error needs a fresh regression pass.

**CURRENT RUN: unified exec session 45191**, .build/debug/ScorecardProbe --replay --call 02-skeptical-operator --interval 3, 141 sentences. Poll this worker; do not duplicate it. Uses revision 3 and all parser fixes. Raw synthetic response bodies (never headers) are under its test-results run. Prior workers 45678, 12100, 48358 and audio test 96257 all completed. A keep-awake assertion is running in exec session 42450 (caffeinate -i -s -t 28200), bounded to ~08:00; do not create another.

## Next actions

1. Poll replay 45191, evaluate its final output, diagnose errors from synthetic response files. Run third long script and rerun first after definition fix. Preserve scoped metrics: mapped checks are not comprehensive all-field precision/recall. Review extra fields and add necessary tests.
2. Implement generic numeric derivations and missing personal/business return-count fields; avoid guessing unknown subcategories. Current catalog is 41 fields and max50.
3. Finish recovery/retry policy, UI resume of persisted pending jobs, immediate configuration switching, Settings field/threshold edits and export, keyboard focus/navigation, and audio reconnect/lifecycle. Current configuration UI switches only after a call, a known gap versus requested immediate switching.
4. Rebuild the app and validate real UI layouts, audio permission/start/stop using synthetic files where possible. Real Google Meet audio and actual sharing invisibility remain unverified; prior screenshot exclusion is not proof for Meet. Calendar connection is optional; automatic naming explicitly deferred to next version.
5. 45-minute soak, release packaging/license/source review/secret scans, reproducible artifact checks, GitHub publish when authenticated, FINAL_REPORT.

## Verification commands

- swift test --disable-sandbox (27 tests passed; module cache envs can point to /tmp/scorecard2-clang and /tmp/scorecard2-swift in sandbox).
- .build/debug/ScorecardProbe --live-sample uses the real OpenAI core with synthetic data; network access required. Do not repeatedly run without a new reason.
- Usage ledger: ignored private-data/api-test-usage.json. Avoid printing credential files.

## External blockers

- OpenAI text AND short synthetic audio roundtrip now pass. Live Meet capture remains unverified.
- Mac was charging at 23:58; at 00:07 it showed AC, 38% and discharging (intermittent). Keep monitoring actual power rather than assuming unlimited runtime.
- No real Google recordings located for live-audio evaluation.
- GitHub release-upload auth and Developer ID/notarization unavailable.
- New-app capture/calendar permissions and actual Meet sharing test pending.
