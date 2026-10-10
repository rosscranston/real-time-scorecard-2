# Real-time Scorecard 2

A native macOS sales-call scorecard with OpenAI Decisions classification, structured fact extraction, and cloud transcription. It supports named calls without Calendar, a JSON-driven interface, company memory, locked manual corrections, evidence, history, replay, and Keychain setup. Each installer supplies their own API key.

This is an alpha build. Real Google Meet capture modes and screen-sharing exclusion still require live verification. See [build and distribution](docs/BUILD_AND_DISTRIBUTION.md) and [architecture](docs/ARCHITECTURE.md). Source is provided under the [MIT license](LICENSE).

**Hackathon download:** [v0.1.0 release](https://github.com/rosscranston/real-time-scorecard-2/releases/tag/v0.1.0) · [verified results and quick demo](FINAL_REPORT.md). The Mac binary requires Apple Silicon and macOS 26 or later and is not notarized.

## Overnight execution

See `OVERNIGHT_PLAN.md` for the October 10, 08:00 Pacific target and `PREFLIGHT.md` for verified blockers. Cloud transcription uses OpenAI; ElevenLabs is excluded.

## Enter your API key

Open `.env` in this directory and put your own OpenAI Platform API key after `OPENAI_API_KEY=`. Create a key at https://platform.openai.com/api-keys if needed. Do not paste it in chat. The file is excluded by `.gitignore`; `.env.example` contains placeholders for distribution. The connection test does not print keys or API error bodies.

For a fresh checkout, copy `.env.example` to `.env` first. Environment variables override file settings. No shell evaluation of the file occurs.

Run from this directory:

```sh
python3 scripts/test_decisions.py
```

This makes one billable API request using synthetic sales text. It checks that software is classified as Drake and hosting as on-premises, and reports confidence and request duration. It does not capture audio, upload customer calls, or update the Mac app. A successful check confirms access for this request, not sufficient credits for a full meeting or achievement of the five-second target.

Without a key or network call:

```sh
python3 scripts/test_decisions.py --dry-run
python3 -m unittest discover -s tests -v
```

Mac Settings provides masked key entry, Save/Remove, and Test text APIs. Use .env for this session explicitly imports a selected developer key into memory without saving it; quitting clears that session key. Packaged apps store keys in macOS Keychain; developer runs can use `.env`. Keys will never be bundled into the downloadable app or exported in criteria JSON.

See `PROJECT_PLAN.md` for components, milestones, defaults, acceptance gates, and a future implementation-goal prompt.

## Starting criteria configuration

`configurations/company-scorecard.draft.json` adapts the supplied 39-field catalog into a 50-field draft, adding exact team size, separate hosting provider, personal/business return counts, staff roles, practice management, annual firm revenue and typical return fee; return counts support JSON-defined calculations. It includes suggested call-type priorities, one answer per field, uncertainty and lock defaults, and extraction routes. The native app and probe load this configuration at runtime. The older Python smoke test uses only its two built-in questions.

The untouched source is stored under ignored `private-data/imports/company-fields.original.json`. Contact/company examples are omitted from the distributable draft. Attio mappings are metadata only and do not enable synchronization or writes.

## Official references

- Decisions API: https://developers.openai.com/api/docs/guides/decisions
- API pricing: https://developers.openai.com/api/docs/pricing
- ChatGPT pricing: https://learn.chatgpt.com/docs/pricing

API-key requests use the API project's billing. Do not assume ChatGPT subscription credits are the same balance; this test reports authentication/quota failures without exposing credentials.

## Build and test the native app

Requires macOS 26 or later and a compatible Swift/Xcode toolchain.

```sh
swift test --disable-sandbox
bash scripts/build-app.sh debug
open "dist/Live Scorecard 2.app"
```

The default build is ad-hoc signed, not notarized. Set SIGNING_IDENTITY explicitly for a certificate you control. Signing alone does not perform notarization.

Enter an event name and press Start; firm name is optional. Calendar is optional in Settings, where Google can be added through macOS Internet Accounts. Automatic Calendar naming is deferred. Transcript input currently supports manual synthetic snippets and post-call debrief. Select OpenAI cloud, Apple Speech, or transcript-only input in Settings. OpenAI has passed a short synthetic audio roundtrip; actual browser/microphone capture still needs live validation.

Paced replay of the supplied synthetic discovery scripts:

```sh
swift build --disable-sandbox --product ScorecardProbe
.build/debug/ScorecardProbe --replay --call 01-owner-story --interval 5
```

Intervals must be 3–30 seconds. Sentence arrivals continue independently of API completion. Reports and synthetic response diagnostics are saved under ignored test-results; the test spending ledger is under ignored private-data. The native Settings replay button loads the same JSON pack and uses five-second intervals. Its UI replay uses the app's own API usage ledger. Use Settings to save your key, or explicitly run ScorecardProbe --save-key to copy your development key into the local app Keychain entry. Neither method includes a key in the app bundle.

## Configuration and controls

Settings → Edit fields changes allowed values, aliases, speaker rules, visibility, and confidence thresholds. Saving creates a new revision; Export JSON includes those edits. Imported JSON can also define call-type ordering and supported numeric calculations. Configurations can switch during a call while retaining prior answers.

Click a field to edit. Edited values lock automatically; arrow keys save and move to the next field. Command-Shift-L toggles a lock, Command-F finds a field, and Command-Z/Control-Z undo typing or a saved manual change. Evidence stays behind +. Unknown values show only a yellow question mark. Collapsed sections remain collapsed and count distinct changed fields.

Settings includes spending estimates, a local API allowance, and raw transcript retention. Company exports and deletion are available in History. Interrupted extraction jobs can resume there without starting audio capture.

For the bounded 45-minute synthetic stress run:

```sh
.build/debug/ScorecardProbe --replay --call 03-partners-corrections --interval 5 --soak-minutes 45
```

This repeats the same synthetic conversation, uses API credits, and measures the core pipeline; it is not a real meeting or a fresh accuracy evaluation. The seven shorter synthetic fixtures use `--short --call call-01-straightforward` (and the other IDs in the short-fixture JSON).


## Verification status

The 45-minute synthetic transcript soak processed 541/541 sentences with no pending jobs. Transcript-to-persistence p95 was 3.84 seconds; batches that changed answers had a 4.12-second p95. Estimated test cost was $0.54. This run used catalog revision 8; the expanded 50-field revision is being evaluated separately. A native short replay on revision 10 measured a 4.72-second p95 visible-row callback over 18 observations. These measurements exclude live audio transcription and are not a Google Meet end-to-end guarantee.

All 46 Swift regression tests currently pass. Native checks verified manual edits/locks, undo, evidence expansion, stored transcripts, and company collapse-state persistence across relaunch. History exposes separate accessible actions. Inconsistent numeric inputs show an explanation behind ! while preserving direct and locked answers.

The shipped catalog permits provisional unlisted names for hosting and document tools. When explicitly named by the customer but not confidently classified, an empty unlocked field can show a red Other answer with the exact source quote. The provisional threshold is 0.30; confirmed styling starts at 0.75 and replacements still require 0.90. These are configurable heuristics, not calibrated probabilities. Listed options and aliases cannot enter this path, and no provisional value replaces an existing answer. Other classification disagreements may receive one focused recheck of at most four fields.
