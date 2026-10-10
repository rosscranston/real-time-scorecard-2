# Hackathon submission · Live Scorecard 2 v0.1.0

**Ready to submit as a working alpha prototype.** The strongest demonstrated path is a paced synthetic transcript feeding a native Mac scorecard through real OpenAI API calls. Live Google Meet capture and screen-sharing exclusion still need a real meeting verification.

## What is implemented

- Native, resizable macOS scorecard with a JSON-driven catalog of up to 50 fields and Initial, Demo, and Review ordering.
- OpenAI Decisions classification plus structured extraction, exact supporting quotes, configurable confidence thresholds, and bounded retries.
- Named calls without Calendar; optional Calendar connection through macOS Internet Accounts.
- Persistent company answers and call history, inline edits that lock, conflict proposals, undo, collapsed-section change counts, and evidence behind a plus button.
- Settings for the user's own API key, Keychain storage, JSON import/export/editing, transcription choice, and a local spending allowance.
- OpenAI cloud transcription implementation and synthetic transcript replay. No ElevenLabs integration or local language model is required.

## Verified evidence

| Check | Result | Scope |
| --- | --- | --- |
| Swift regression tests | 46 passed, zero failures | Latest code; locks, evidence, queue, parsing, calculations and guarded updates |
| 45-minute synthetic transcript soak | 541/541 sentences processed; no pending jobs | Earlier catalog revision 8; transcript to persistence p95 3.84 seconds, changed batches p95 4.12 seconds |
| Native synthetic replay | Visible-row callback p95 4.72 seconds over 18 observations | Catalog revision 10; excludes audio and physical frame timing |
| Targeted corrected-hosting transcript | 20/20 rubric checks; p95 4.65 seconds | Catalog revision 14; unlisted hosting names remain provisional/red |
| Targeted unsupported-hosting transcript | 13/13 rubric checks; p95 2.17 seconds | Catalog revision 14; seller examples and negated/unknown hosting do not populate answers |
| Short synthetic audio roundtrip | Drake Desktop, team size 6 and 800 returns extracted | Generated speech through cloud transcription; not a Google Meet recording |
| Native controls | Launch, settings, edits/locks, undo, history, evidence and collapse persistence checked | Existing local installation; downloaded installation on a second Mac remains untested |

These are bounded synthetic checks, not comprehensive precision/recall measurements or an end-to-end latency guarantee. Some earlier test runs exceeded five seconds. Three longer revision-14 replays are still running at the submission checkpoint and are not counted as passed here. The release packaging script scans app/source archives for credentials and private runtime files and supplies hashes and the exact source commit.

## Quick demo

1. Download and unzip the Mac app from the GitHub v0.1.0 release. It requires **Apple Silicon and macOS 26 or later**.
2. Open Settings, enter your own OpenAI Platform API key, save it to Keychain, and select **Test text APIs**. API usage is billed to that key's project.
3. For a reproducible demo without microphone/Calendar permissions, select **Replay synthetic conversation JSON…** and choose the release's `synthetic-short-calls.json` fixture (also in `tests/Fixtures` in the source).
4. Watch fields populate at five-second sentence arrivals; expand evidence, edit a value, and observe that it locks. Replay uses API credits.
5. For manual calls, choose transcript-only input, enter an event name and press Start; add synthetic text through the transcript panel. A stable firm name carries answers forward.

## Release limitations

- The app is ad-hoc signed, **not Developer ID signed or notarized**. A downloaded copy may require macOS per-app approval; managed Macs may block it. Source is available for local builds.
- Actual Google Meet microphone/browser capture, reconnect behavior in a real call, and screen-sharing invisibility are not yet verified. Do not rely on the visibility setting as a privacy guarantee.
- Five-second performance is measured on specific transcript replays, not audio-to-screen. Confidence thresholds are heuristics, not calibrated probabilities.
- Automatic Calendar naming, automatic alias learning, and broader shortcut customization remain follow-up work. Calendar is optional.
- Each user supplies their own API key; no credentials or customer recordings are included in the release.

Source and release: https://github.com/rosscranston/real-time-scorecard-2

License: MIT. See `docs/BUILD_AND_DISTRIBUTION.md` for build, installation and privacy details.
