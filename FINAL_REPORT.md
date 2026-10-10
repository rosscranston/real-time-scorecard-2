# Live Scorecard 2 v0.1.1 · alpha release

Current source and Mac app release: https://github.com/rosscranston/real-time-scorecard-2/releases/tag/v0.1.1

This publishes the current development version at the user's request. It includes a usable native scorecard and synthetic demos, but it does **not** meet every accuracy or latency acceptance gate. The original hackathon v0.1.0 release remains available unchanged.

## Changes since v0.1.0

- Paced audio-file replay through OpenAI in Settings, with explicit speaker selection, a five-minute limit, and cancellation; no microphone or browser capture is opened by this test path.
- Deterministic inferred arithmetic and a configurable tolerance for rounded percentage comparisons, preserving stated and locked values.
- Shorter text request deadlines and conservative usage records for failed/cancelled requests.
- An experimental Decisions check of the exact proposed annual return quantities and supporting context, intended to separate whole-firm volumes from pilot samples and proposed purchases.
- An acceptance audit, clearer API-key setup, and additional synthetic regression coverage.

## Verified evidence and known failures

- **54 Swift tests pass** (51 core and3 audio). They cover parsing, locks, versions, persistence, bounded queues/reconnects, numeric calculations and evidence gates. Offline tests do not establish model accuracy.
- Latest exact-candidate gate test (`call-08-annual-versus-pilot`, source02b4530, catalog16, three-second arrivals):11/11 sentences processed, no pending work or terminal error; **5/7 final checks pass**. Annual total stayed1260 instead of the corrected1280, so the percentage was also wrong. p95 arrival-to-save **6.15s**; the five-second target was not met. Other current regression calls were still running when this release report was prepared; they are not claimed passed here.
- Three prior long replays all completed (127,141,151 sentences), but changed-update latency failed in each. First two used catalog14 and passed22/22 mapped checks each; third used catalog15 and passed19/22, confusing pilot quantities and annual firm volume. These were the reason for the new gate, not proof the issue is fully solved.
- Earlier45-minute synthetic soak:541/541 processed; p95 arrival-to-save3.84s and changed batches4.12s, on catalog8. This is historical evidence of queue endurance, not current end-to-end performance.
- Native generated-speech replay (6.20s) populated Drake Desktop, team6 and800 annual returns. Three visible-row callbacks had p954.13s from the VAD boundary. Stop during a silent lead-in prevented later speech ingestion. These audio checks preceded catalog16.
- Native numerical replay verified derived77.19%, stated77.2% without a false conflict, and stated80% with a valid conflict. Native editing/locks, undo, evidence, history and collapse persistence were also inspected.

These results are scoped synthetic checks, not comprehensive95% precision/90% recall or real Google Meet validation. API usage is billable to each user's own key.

## Quick start

1. Download and unzip the Mac app. It requires **Apple Silicon and macOS26 or later**.
2. Open Settings, enter your OpenAI Platform API key, save it to Keychain, and select **Test text APIs**. No developer environment file is required.
3. Select **Replay synthetic conversation JSON…** and the release's `synthetic-short-calls.json` for the transcript demo. For a recording, select its speaker and **Replay audio file through OpenAI…**.
4. For live calls, enter an event name and press Start. Calendar is optional. Live capture may request microphone and screen/system-audio permissions.
5. Review numerical evidence and manually correct/lock important values. Locking prevents automatic replacement.

## Distribution and remaining gates

The release is ad-hoc signed, **not notarized**; macOS per-app approval or a local source build may be needed, and managed Macs may block it. Actual Meet capture, remote screen-sharing invisibility, interference while on a call, and a second-Mac installation remain unverified. Automatic Calendar naming, learned aliases and comprehensive shortcut customization are deferred. No credentials, databases, private recordings or customer transcripts are included in the release.

App/source ZIPs, SHA256SUMS.txt and SOURCE_COMMIT.txt identify the exact packaged source. See docs/BUILD_AND_DISTRIBUTION.md and docs/ACCEPTANCE_AUDIT.md. Source is MIT licensed.
