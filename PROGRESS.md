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

## Current stage (00:31 Pacific)

The independent native app builds and launches. 34 Swift tests pass, including numeric dependencies, confidence/locks, out-of-order audio completion, bounded retries, and configuration switches while a request is in flight. Five earlier Python harness tests also passed. Latest test output: /tmp/scorecard-tests.log.

Implemented since the previous checkpoint:
- Catalog revision 5: 43 fields, 35 automatically extracted; personal/business return counts and six JSON-defined numeric formulas. Calculations require two direct/locked inputs, retain evidence, respect locks, and avoid circular derivation.
- Three-attempt bounded retries for malformed final responses, network failures, and HTTP 5xx. Quota/auth/budget/rate-limit failures remain explicit stops. Attempts persist across restarts.
- Immediate configuration switching: transactional replacement queue, archived previous configs/facts, generation check that rejects late old-config results. Removed fields do not enter model context.
- History exposes Resume pending jobs, without starting capture. Settings edits allowed values, aliases, source policies, visibility/extraction rules and confidence thresholds, then saves an exportable revision.
- Keyboard navigation saves/locks edited field and focuses the next. Mere navigation does not lock or clear values. Configurable lock shortcut. Verified Down from number of returns after typing 800, typing 6 in team size, Return, then Command-Shift-L unlock.
- UI settings revision save and manual Start without Calendar verified. App initially appeared unresponsive through CUA; process sample showed it idle/responsive, and rebinding cua.getApp fixed automation. Not an app hang.
- Bundled config update preserves a user-created revision with the same number instead of failing initialization.

App bundle in dist is a launchable ad-hoc debug build with the new settings/keyboard/audio, but it predates the final-answer phase parser and revision-5 definitions. Rebuild for delivery. Local UI is on a synthetic history company with returns800 locked and team6 unlocked; transcription preference is temporarily transcript-only for testing. Restore OpenAI cloud before final handoff. Local UI saved config revision5 is the older catalog4 content; bundled revision5 will safely become revision6 on launch, and existing selection remains preserved.

## Audio and connectivity

OpenAI text and AUDIO access are verified. At ~00:07 the adapter transcribed generated 7.58-second Samantha speech, then passed software=Drake Desktop, employee_count=6, number_of_returns=800 through the real core pipeline. Files in test-results/audio. This does not verify real Meet/audio-to-screen latency. Earlier quota/rate-limit blocker is resolved for this request.

Audio implementation: selected-browser plus microphone ScreenCaptureKit channels, bounded streams, PCM conversion, client voice turns, gpt-live-transcribe WebSocket, stable client IDs through out-of-order acknowledgments, final transcript ingestion. Apple Speech is explicitly optional. No ElevenLabs/local LLM. Automatic audio reconnect and actual capture/start/stop lifecycle still need work; explicit reconnect exists. Never silently claim lost audio succeeded.

GitHub CLI authentication now VERIFIED for rosscranston with repo/workflow scope. No remote/repo published yet. Developer ID/notarization remain unavailable; source and explicitly labeled ad-hoc app can be shared.

Power risk: at 00:31 Mac reported AC but 33% battery, discharging, estimated2:16 remaining. User warned in commentary to check stronger charger/cable. Bounded caffeinate process session42450 remains; do not duplicate. Power is a real overnight risk, not a reason to stop independent work.

## Replay results and current worker

Call1 recovered full127 sentences in test-results/01-owner-story-1791615393, but old rubric12/13: proposed purchase240 incorrectly replaced actual684. Old revision2 definitions. Initial parser problems recovered; not an uninterrupted latency pass. Needs fresh replay after definition fixes.

Call2 test-results/02-skeptical-operator-1791616259 stopped37/39 on differing intermediate/final documents, p952.57 before stop. Worker45191 ended. Needs fresh full replay with latest parser/catalog.

Call3 test-results/03-partners-corrections-1791616869 completed151/151, zero pending/error,13/15 mapped checks; p955.54s and142/151 within5seconds (94.0%, targetnotmet). Failures: firm location replaced with participant visiting Boise; software remained Drake edition-unconfirmed despite later desktop clarification. Other software changed from practice management to accounting; manually review unscored fields. Five malformed-looking responses were actually commentary plus final_answer messages; parser now selects final_answer phase per official Responses API. That fix should eliminate unnecessary retries; regression test added. More specific location/software/practice-management rules and previous-answer evidence context added, catalogrev5. Never assume improvements passed without new result.

CURRENT LIVE RUN: exec session8174, .build/debug/ScorecardProbe --replay --call 03-partners-corrections --interval3. Log /tmp/scorecard-replay-03b.log. Uses latest parser and catalog5. Poll it; do not start duplicate API runs sharing ledger. Previous run68098 and test16293 ended. Latest Swift tests48029 completed34/34. Other stale handles need not be polled.

Synthetic rubric now15 checks percall including personal/business counts. scripts/evaluate-replay.py writes scoped evaluation, not all-field precision. Original answer keys never enter inference. Raw synthetic responses are ignored/private; do not publish diagnostics. Test ledger private-data/api-test-usage.json is far below$5 but avoid concurrent writers.

## Next actions

1. Finish current03 rerun and evaluate; fresh02 then01. Review additional populated facts and cross-sentence correctness. No fabrication of comprehensive accuracy or audio-to-screen SLO.
2. Finish bounded audio reconnect/lifecycle verification, pending recovery UI test, config switch UI test, and any remaining requirement gaps. Inspect PROJECT_PLAN/OVERNIGHT_PLAN and current source.
3. Actual capture/permissions with synthetic audio where feasible; real Google Meet and sharing exclusion remain unverified. Calendar optional connection implemented; automatic naming explicitly next version.
4. Start meaningful45-minute soak soon; prefer completing independent packaging while it runs. Keep battery/deadline risk in mind.
5. Release packaging, license, source/secret scan, clean GitHub repository/release, source/appZIP/checksums, reproducible verification, FINAL_REPORT by08:00. No Developer ID means label app non-notarized. Do not push old parentrepo/private files.

## Verification

- env CLANG_MODULE_CACHE_PATH=/tmp/scorecard2-clang SWIFT_MODULECACHE_PATH=/tmp/scorecard2-swift swift test --disable-sandbox
- bash scripts/build-app.sh debug (or release)
- python3 scripts/evaluate-replay.py test-results/<run>
- API key remains ignored.env and native Keychain; never print keys.

Official phase documentation: https://developers.openai.com/api/reference/resources/responses/methods/create
