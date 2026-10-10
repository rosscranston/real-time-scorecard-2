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

Core implementation is built and verified; the native app currently has a temporary placeholder screen. Live scorecard UI, AppStore orchestration, Settings, capture/transcription, calendar/history, and release packaging remain to be implemented. Do not mistake the CLI probe or placeholder window for completion.

## Next actions

1. Implement observable app store with copied-state database commits, queue/retry and company/call selection.
2. Build approved scorecard UI and native Settings/Keychain interface; wire real synthetic transcript replay into it.
3. Reuse/adapt the old audio buffer/capture code; add OpenAI streaming transcription and optional explicit Apple Speech.
4. Connect calendar/history/debrief; validate UI and build packaged app.
5. Broaden labeled replay evaluation and protect release/verification time.

## Verification commands

- swift test --disable-sandbox (18 tests passed; module cache envs can point to /tmp/scorecard2-clang and /tmp/scorecard2-swift in sandbox).
- .build/debug/ScorecardProbe --live-sample uses the real OpenAI core with synthetic data; network access required. Do not repeatedly run without a new reason.
- Usage ledger: ignored private-data/api-test-usage.json. Avoid printing credential files.

## External blockers

- OpenAI Realtime returned credit_balance_exhausted; text API probes succeeded.
- Mac needs external power for overnight runtime.
- No real Google recordings located for live-audio evaluation.
- GitHub release-upload auth and Developer ID/notarization unavailable.
- New-app capture/calendar permissions and actual Meet sharing test pending.
