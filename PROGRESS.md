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

## Current stage (01:00 Pacific)

40 Swift tests pass (latest /tmp/scorecard-tests.log at00:58) and8 Python tests pass. Release Swift build succeeds after an escalated retry: sandbox blocked Xcode dSYM generation; the ordinary build was not an application failure. Native release bundle exists in dist, but rebuild again from the final committed source before packaging.

New work since checkpointa438bda:
- Audio connection protocol plus bounded reconnect: retain at most12 unfinished turns; two reconnects per channel lifetime, original client IDs/timestamps, old-connection generation rejection, duplicate completion suppression, eight-second final drain. Quota/auth/budget/protocol errors do not retry. Four disconnect/drain/queue tests and an audio-budget-before-upload test pass.
- Actual7.58-second generated audio → OpenAI → transcript → software/team/returns passed again with the revised transport. Not a live Meet test.
- Audio uploads reserve estimated cost before sending (including retransmission). Settings shows text/audio spending, current-call timing, cumulative local allowance(default$5), and80%warning. No billing changes/purchases.
- Local transcript retention defaults30days; cleanup on launch preserves company facts/evidence/history and calls with pending work. History supports companyJSON export and confirmed company deletion. Offline retention/deletion test passes.
- Visible-row update callback timing added (not physical display scan-out), brief update highlight, Command-F search, native typing undo, configurable lock shortcut. Evidence/proposal/edit state resets on context changes; editing captures context identity to prevent stale edits entering another company.
- Added5 shorter synthetic call fixtures from the old project's labeled synthetic set, stripped inference input of answer keys/source notes. CLI --short selects them; rubrics map supported canonical fields.
- Added --soak-minutes45:541 sentences at5second intervals over45minutes, fixed arrival deadlines. Reports add CPU time/peakRSS, configrevision/hash, and update-batch latency distribution.
- Added MIT LICENSE, THIRD_PARTY_NOTICES, architecture/build/distribution docs, clean-commit release packaging, ZIP credential/runtime-data scan and checksums. Scanner tests reject fake credentials without echoing them, private files, and unsafe paths. Actual ZIP generation/scans/clean install still pending.

Current catalogrevision9 (43fields/35automatic). Revision6 tightened hosting provider vs generic cloud; revision7/Other description distinguishes named unlisted products from unknown; revision8 reconciles user-specified GruntWorx with GruntWorks alias and cleans stale draftnotes; revision9 prevents generic closing remarks replacing a substantive high-level note. Current soak intentionally holds its loaded revision8; only the note rule changed afterward. Short-fixture tests still need to run on revision9.

## Current live worker

**Exec session77138 is the45minute paid soak**, started~00:56. Command: .build/debug/ScorecardProbe --replay --call03-partners-corrections --interval5 --soak-minutes45. Log /tmp/scorecard-soak-45.log.541sentences; should finish~01:41. Poll this same handle; do not start another API process writing the shared test ledger. It uses final-answer parsing, explicitOtherdescription, catalog8. The full first/second/third calls listed below have ended. Other build/test handles are terminal.

Keep-awake session42450 still bounded to08:00; do not duplicate. Power RESOLVED: Mac nowAC,54%,charging at00:53. Earlier discharge warning was delivered and no longer applies.

## Current replay evidence

- Call1 latest: test-results/01-owner-story-1791618558,127/127,15/15 mapped checks, all127≤5sec,p952.54s,estimated$0.10863. Annual firm684 preserved instead of proposedpurchase240. ProcessCPU4.57sec across379wallsec, peakRSS26.1MB for CLI only, not UI/Meet performance. Five additional populated fields reviewed/inneedofreview; high_level_note was a generic closing remark, now addressed by catalog9 but not yet revalidated.
- Call2 latest: test-results/02-skeptical-operator-1791618099,141/141,14/15,p952.49s. Missing document portalShareFile: Responses had validOther+detail, Decisions confusedOtherwithunknown/lowconfidence. Improved explicitOtherdescription and document-portal rule after run; must verify with short cases and/or targeted follow-up. Five extra populated fields need semantic review.
- Call3 latest standalone: test-results/03-partners-corrections-1791617468,151/151,14/15,p952.42s. Location andDrakeedition fixes passed. Hosting remained genericvendorcloud because the firstcloudstatement was overinterpreted and providerrefinement wasn't emitted into both fields. Fixed catalog6 and currently exercising it in45minute soak. Four extra fields need review.
- Earlier call3 test-results/03-partners-corrections-1791616869:13/15,p955.54s. That run treated intermediatecommentary as schemaoutput and retried; final_answer phase parser fixed it and the latest2.42srun proved the speed improvement.
- Earlier call1recovered run and call2incomplete runs remain historical diagnostics; never count as completed latencypasses.

Rubric is explicit supported final-field checks, not exhaustive precision/recall across every intermediate commitment. Do not claim95%all-answer precision from these partial checks. Raw synthetic response bodies remain ignored undertest-results. Total test ledger was~$0.716 at00:55, wellbelow$5, plus tinyseparate nativeUIledger. No simultaneous test-ledger writers.

## UI and connectivity status

Actual UI verified in prior turn: manualevent→StartwithoutCalendar, four live text values, inlineediting/autolock/undo, Settings fieldeditorvalues/aliases/thresholds and savingrevision, keyboard800→Down→team6→Return→CommandShiftLunlock. New retention/budget/search/context-reset controls compile but still need UIinspection. Window privacy policy remains requested; actual Meet sharemode test unverified.

Current open native app may still be the previous running build. Local app data is synthetic; selectedcompany has800returnslocked,team6unlocked. Transcription preference is temporarilytranscript-only; restoreOpenAIcloud and selectlatestbundledcatalog before finalhandoff. Key is in Keychain andignored.env. Never print it.

GitHubauth VERIFIED rosscranston. Read-only check: rosscranston/real-time-scorecard-2 does NOTexist; suitablededicateddestination. No remotepublication yet. Oldparentrepositorymustnotbepushed. DeveloperID/notarization unavailable; share clearly labeled ad-hocAppleSiliconbuild or source.

## Next actions

1. While77138soak runs, commit current work, run scripts/package-release.sh (may need escalation forXcode dSYM), inspect archive scans and perform clean-source rebuild/moved-app launch. Do not claim finalartifacts until actuallyverified. Regenerate after any subsequent fixes.
2. Native UIinspection of new controls, dynamicconfigswitch duringcall, pendingrecovery, longvalue/evidence/collapsebehavior and resizedlayout. RestoreOpenAIdefault afterward. No unattended live-room microphone capture; synthetic/filetests only. RealMeetpermissions/capture/sharing require usertrial and remain explicitpendinggates.
3. Aftersoakterminal, evaluate and run five shortcases sequentially (--short withIDs in tests/Fixtures/synthetic-short-calls.json). Verify Other/midpoints/negation/forecast/newfirm and review extra populatedvalues. Consider targetedmissingShareFile andhostingrefinement checks, notendlessfullreruns. Report actualconfigrevision.
4. Finish release README/FINAL_REPORT, cleanGitHubsource and releaseassets, appZIP/sourceZIP/SHA256SUMS/sourcecommit. Sourcearchive must correspond to committedbinaryinputs. No secrets/customerdata/diagnosticfiles.
5. Completion audit allrequirements; fullgoal staysactive while functionality/requiredverification remains. External actualMeettrial may remain pending; don'tclaim complete based only on syntheticbenchmarks.

## Commands

- env CLANG_MODULE_CACHE_PATH=/tmp/scorecard2-clang SWIFT_MODULECACHE_PATH=/tmp/scorecard2-swift swift test --disable-sandbox
- PYTHONPYCACHEPREFIX=/tmp/scorecard-python-cache python3 -m unittest discover -s tests -v
- bash scripts/build-app.sh release
- bash scripts/package-release.sh (requirescleancommittedsource; generatesdistZIPs/checksums/sourcecommit)
- python3 scripts/evaluate-replay.py test-results/<run>
- Usage: ignoredprivate-data/api-test-usage.json. NoAPIkeys in output.
