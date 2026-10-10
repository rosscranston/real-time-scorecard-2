# Progress

## Current checkpoint — October 10, approximately 01:41 Pacific

This section supersedes older checkpoints. Goal remains active; native tests and release work are progressing.

- Dedicated **public source repository published**: https://github.com/rosscranston/real-time-scorecard-2 . `origin/main` verified at `3655b228d0ce33b6ab7263a42abde8e76d3139b5`. Full-history privacy scan checked 133 blobs with zero findings; audit lives in ignored `private-data/git-publication-audit.json`. No release assets yet. Do not recreate the repository or push the old project.
- Native UI observation recovered with a fresh app bind. Replayed values visibly appear in the accessibility tree. Settings reported transcript-to-save p95 **4.62s**, visible-row callback p95 **4.72s**, 18 visible observations. This is the first short synthetic replay, not live audio-to-screen.
- Evidence stayed behind + and revealed the exact customer quote only when opened. Firm Profile collapse persisted across quitting, rebuilding, relaunching, and opening company answers in History. Stored full transcript verified readable.
- Found History's List rows hid individual action buttons from accessibility. Replaced rows with a lazy scroll stack; Company answers, Transcript and More are now individually accessible and native navigation passed.
- Added persisted optional calculation-conflict explanations. Contradictory direct numbers are preserved and marked !; invalid negative calculated values are never displayed. Conflicts clear when inputs agree. Updated numeric regression test; all **42 Swift tests pass** (`/tmp/scorecard-conflict-tests.log`). Release build passed (`/tmp/scorecard-history-release.log`). Native test temporarily changed total 1240 to locked 100: ! explained 980+260=1240; Undo restored 1240, unlocked, and cleared all conflict indicators.
- Latest source changes (history/accessibility and arithmetic indicators) are not committed yet. Running app was rebuilt from these changes, with formatting-only edits afterward. Session .env key was cleared on quit; local Keychain remains available but may need explicit approval. Audio is stopped and no capture occurred.
- Soak session 77138 remains live, approximately sentence 527/541 at 01:41; finish around 01:42. Current binary/configuration remain its originally loaded v8. Do not start another CLI paid probe until it exits. Next run all six short fixtures using latest 50-field v10, then rerun long cases to validate expanded catalog and prior rule fixes.

## Current checkpoint — October 10, approximately 01:32 Pacific

This section supersedes the earlier checkpoint below. The prior goal turn made concrete release fixes and packaged commit 736f7a8. This turn continues implementation and verification; the goal is active.

- Catalog **revision 10 now has 50 fields / 42 automatic**. Added the explicitly requested annual firm revenue, typical per-return fee, admins, preparers, reviewers, CPAs and practice management. Both configuration copies match. The supported maximum is still 50.
- Expanded long/short fixture rubrics for the added staff/practice fields and negative revenue/fee checks. Added `call-06-finance-ranges` with synthetic midpoint, overlapping-role and seller-price distractor cases. These new CLI checks still need running after the soak; do not rescore older 43-field runs as if they used the expanded catalog.
- Bounded the active job page to 128 while retaining overflow on disk. Recovery orders by transcript sequence rather than second-resolution creation time. Configuration switching supersedes disk overflow too. Two new meaningful tests cover 300 queued sentences/restart/order/no-loss and 140 pending jobs/config switch. **42 Swift tests pass**, log `/tmp/scorecard-paged-queue-tests.log` at 01:21.
- Added explicit Settings → Use .env for this session. It reads only a user-selected local .env key into memory, without altering Keychain. Native import succeeded, then **Test text APIs succeeded in 2.78 s with catalog 10**. Keychain authorization remains a separate first-launch issue for a key created by a differently signed build; session import is a usable alternative.
- Native JSON picker testing found Open disabled for local files. File selection is now explicit and custom type associations are tolerated; actual JSON decoding/schema validation remains required after choosing a file. Both replay and configuration import use the fix. Native replay file selection succeeded.
- A real **native-app replay** of the first short fixture completed: call `48A689FE-17AB-4D06-B85D-6F190A3FD3B9`, 13 segments, all 13 jobs completed, 08:28:46–08:29:48 UTC, catalog 10. Read-only local SQLite inspection verified staff 2/6/2/4, practice management Canopy, 1,240 total / 980 personal / 260 business, UltraTax, Rightworks hosting/provider, Other: SmartVault, correct firm/contact/location. Revenue/vendor-price distractors did not populate financial fields. Unscored extras include competitor GruntWorx and other software Canopy; review their semantics before claiming precision.
- The UI observer started timing out after replay file selection. Unlike the earlier Keychain issue, a process sample (`/tmp/scorecard-replay-ui-sample.txt`) showed the app idle in its event loop, and persisted replay work completed normally. CUA reset/rebind did not restore observation. Do not restart the replay or claim visible-update/collapsed-count verification from SQLite evidence alone. App process 93075 was alive; revalidate before acting. The CUA runtime was reset and the current `app` binding may be undefined after failed getApp calls.
- App audio preference remains OpenAI cloud; native replay does not capture audio. Config v10 was selected and persists. Session key remains in the currently running app until quit. The release binary builds (`/tmp/scorecard-catalog50-build.log`). ZIPs currently refer to 736f7a8 and must be regenerated after these changes are committed.
- Soak **session 77138** still live, last observed beyond sentence 418; due approximately 01:41. It intentionally uses its original catalog 8 and loaded binary. No duplicate probe. Keep-awake 42450 unchanged. Estimated ledgers at about 01:30: probe $1.14274, native UI $0.01492; combined well below $5.
- Next: finish source/history privacy audit and dedicated GitHub source publication; finish soak and run short fixtures sequentially, then targeted/full expanded-catalog checks justified by failures; reconcile FINAL_REPORT and package exact committed source. Real Meet capture/share/audio-to-screen and notarization remain unverified. GitHub CLI auth was verified earlier but no remote exists yet.

## Earlier checkpoint — October 10, 01:16 Pacific

The native app, extraction core, configuration editor, company persistence, and release tooling are implemented. The overnight goal remains active. Deadline: 08:00 Pacific. No sub-agents are authorized.

### Verification completed

- 40 Swift tests pass (`/tmp/scorecard-keychain-tests.log`, 01:16); 8 Python harness/release-scanner tests passed earlier.
- Release compilation succeeds. Xcode dSYM generation needs an escalated build in this environment; this is a sandbox constraint.
- Commit `c856f89` was packaged successfully. Both ZIPs passed credential/private-data/path scans and the app passed ad-hoc signature verification.
- Exported source rebuilt successfully in `/tmp/scorecard-release-check-c856f89/RealTimeScorecard2-0.1.0`; log `/tmp/scorecard-clean-build.log`.
- The extracted app launched outside the source folder and loaded its bundled configuration and saved settings. Its resource accessor contains no developer-directory fallback.
- Native UI verified: manual Start without Calendar (earlier build), live text extraction, inline edits/autolock, undo, field settings/version save, arrow navigation/lock shortcut, persistent history, retention/spending controls, and Command-F search after the focus fix described below.
- Two generated 7.58-second speech → OpenAI transcription → extraction smoke tests passed; latest used the revised reconnect adapter. Expected Drake Desktop, team 6, and 800 returns were recovered. This is not a live Meet test.

### Release-test fixes in this checkpoint

1. Reading a Keychain item created by the CLI blocked the packaged app's main thread while macOS waited for authorization. A process sample identified `SecItemCopyMatching` as the blocker. All app credential operations now run off the main actor. Start and history recovery show a connecting state and prevent duplicate starts. Start uses noninteractive reads; explicit Settings → Test text APIs may request authorization. Legacy file-based Keychain reads additionally preserve/restore the process interaction flag under a shared lock because LAContext alone did not suppress the ACL prompt. Verified that Start promptly returned an authorization error and the UI stayed responsive. Error -25293 is now mapped to an actionable Settings message. No Keychain ACL was weakened or bypassed.
2. Command-F selected a field but did not focus its editor. The editor now requests focus after mounting. Native verification: search “team,” type 7, Return → team 7 locked. Command-Z was then invoked to restore the prior value; recheck the resulting value when reopening the section.
3. Restored the saved audio preference to **OpenAI cloud**. No microphone/browser capture was started.

The latest app is running from `dist/Live Scorecard 2.app`. Configuration v9 is selected. Its saved CLI-created key may still need the user's macOS authorization in Settings. Do not confuse this local credential-access gate with API billing: Decisions, Responses, and cloud transcription have all succeeded through the test harness. New users enter their own key in Settings.

**Existing ZIPs are now stale** because the credential/focus fixes postdate c856f89. Regenerate from the next clean committed revision before publishing.

## Implemented components

- Native SwiftUI black/green compact resizable panel; yellow question marks, low-confidence red, provenance dots, collapsed sections with distinct changed-field counts, evidence behind +, locked proposals, hover values, keyboard editing and search.
- JSON configuration up to 50 fields, dynamic groups/layouts, enum aliases and Other details, speaker policies, thresholds, import/export/versioning and field editor. Current catalog v9: 43 fields, 35 automatic.
- SQLite company truth, history/transcripts, call-type layouts, pending jobs, immutable change events, manual locks/proposals/undo, source/evidence validation, stale-job rejection, clear watermarks and configuration isolation.
- Concurrent OpenAI Decisions classification and strict Responses extraction; final-answer-only parsing, enum agreement, confidence gating, exact quote validation, coalescing, bounded retry and quota circuit breaking.
- Numeric midpoint handling and JSON formulas for total/personal/business counts and percentages, avoiding circular calculations.
- OpenAI cloud transcription with independent meeting/microphone channels, bounded pending audio turns, two reconnects, original IDs/timing, duplicate suppression, final drain, and estimated spending reservation before upload. Apple Speech remains an explicit optional selection; no ElevenLabs.
- Optional Calendar access via macOS Internet Accounts; manual event and firm naming works independently. Automatic calendar naming deferred.
- Keychain and ignored developer .env credentials; estimated local API allowance, raw transcript retention, company export/deletion, pending-history recovery without audio.
- MIT license, architecture/distribution docs, clean-commit packaging, credential/runtime-data ZIP scans, checksums and source-commit manifest.

## Live processes — do not duplicate

**Exec session 77138:** 45-minute paid soak, started approximately 00:56; expected finish approximately 01:41.

```sh
.build/debug/ScorecardProbe --replay --call 03-partners-corrections --interval 5 --soak-minutes 45
```

Log: `/tmp/scorecard-soak-45.log`. It schedules 541 sentences at fixed five-second deadlines. Last seen beyond sentence 198, processing normally. It loaded catalog v8; v9 only changes the high-level-note rule. The process continues using its already-loaded binary despite subsequent builds.

**Exec session 42450:** bounded `caffeinate` through approximately 08:00. Mac last observed on AC and charging. Do not duplicate.

All release/build/test sessions in this checkpoint are terminal. Do not run another paid probe until session 77138 ends: the test spending ledger is not cross-process locked. Native UI uses a separate ledger; combine both when assessing the $5 overnight cap.

## Replay evidence

| Run | Sentences | Mapped final checks | Transcript pipeline p95 | Notes |
| --- | --- | --- | --- | --- |
| `01-owner-story-1791618558` | 127/127 | 15/15 | 2.54 s | All sentences ≤5 s. Annual 684 preserved instead of purchase 240. Estimated $0.10863. CLI CPU 4.57 s / 379 s wall, peak RSS 26.1 MB. |
| `02-skeptical-operator-1791618099` | 141/141 | 14/15 | 2.49 s | Missing ShareFile document portal; explicit Other description/rule refined after this run. Needs revalidation. |
| `03-partners-corrections-1791617468` | 151/151 | 14/15 | 2.42 s | Location and Drake edition correct. Hosting generic cloud needed Verito refinement; rule fixed in v6, now exercised by soak. |

Directories are under ignored `test-results/`. These are supported final-field checks, not exhaustive precision/recall of every intermediate answer. Extra populated fields need semantic review. The call-1 high-level note degraded to a generic closing remark; v9 addresses it but needs revalidation. Earlier incomplete/recovered runs are historical diagnostics, not latency passes.

Five shorter synthetic fixtures are ready in `tests/Fixtures/synthetic-short-calls.json`; inference inputs contain no answer keys. Expectations are in `tests/Fixtures/discovery-expectations.json`. Run them sequentially after the soak using `--short --call <id>`. IDs can be read from the fixture; do not invent them. Test ledger was approximately $0.716 before the soak, comfortably below $5; read current totals before more paid work.

## External gates and distribution

- GitHub CLI authentication verified as `rosscranston`. Dedicated `rosscranston/real-time-scorecard-2` did not exist on read-only check. No remote or public release yet. User authorized publication of a clean dedicated repository/release.
- Never push the old parent repository at `/Users/rossgates/AI/codex-migration/projects/live-call-scorecard-2`; it includes unrelated private data.
- Developer ID/notarization unavailable. Share clearly labeled ad-hoc Apple Silicon app plus source; managed Macs may need administrator approval.
- Actual Meet permissions, browser/microphone capture, screen-sharing exclusion and audio-to-screen p95 are still unverified. Do not capture unattended room audio or claim synthetic replay proves these gates.
- Local app Keychain authorization may need the user after changing an ad-hoc binary. The new UI stays responsive and gives an explicit Settings action.

## Next actions

1. Commit this checkpoint, rebuild/scan archives from that exact commit, and repeat moved-app startup with the corrected build. Retain accurate ad-hoc/alpha labeling.
2. Finish native checks where possible without live audio: collapsed persistence, evidence/long-value behavior, configuration switching, recovery, and resizing. Stale error text now clears when opening a company. OpenAI cloud preference is already restored.
3. After soak completion, evaluate it, then run five short cases sequentially. Revalidate ShareFile Other, Verito hosting, note stability, numeric midpoint/negation/new-practice cases. Review unscored populated facts and report the evaluation scope honestly.
4. Write FINAL_REPORT.md with actual artifacts, checksums, build/test/replay results, cost and incomplete gates. Publish clean dedicated GitHub source and release assets if auth still works.
5. Keep the goal active while required work remains; final delivery must state the real Meet/signing/credential-approval limitations explicitly.

## Useful commands

```sh
env CLANG_MODULE_CACHE_PATH=/tmp/scorecard2-clang SWIFT_MODULECACHE_PATH=/tmp/scorecard2-swift swift test --disable-sandbox
PYTHONPYCACHEPREFIX=/tmp/scorecard-python-cache python3 -m unittest discover -s tests -v
bash scripts/build-app.sh release
bash scripts/package-release.sh
python3 scripts/evaluate-replay.py test-results/<run>
```

The app's runtime and the probe's diagnostics are ignored. Never print .env, Keychain contents or API headers.
