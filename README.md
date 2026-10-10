# Real-time Scorecard 2

This workspace contains the implementation plan and an independent Swift app under development. The core supports the JSON catalog, SQLite company state, correction rules, and a real OpenAI Decisions + Responses pipeline. The native interface is still being connected; this is not yet a release build.

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

The planned Mac Settings > Connections screen will provide masked key entry, Save/Remove, and Test connection. Packaged apps will store keys in macOS Keychain; developer runs can use `.env`. Keys will never be bundled into the downloadable app or exported in criteria JSON.

See `PROJECT_PLAN.md` for components, milestones, defaults, acceptance gates, and a future implementation-goal prompt.

## Starting criteria configuration

`configurations/company-scorecard.draft.json` adapts the supplied 39-field catalog into a 41-field draft, adding exact team size and separate hosting provider. It includes suggested call-type priorities, one answer per field, uncertainty and lock defaults, and extraction routes. It is not yet a runtime-supported schema; the existing synthetic API test still uses its two built-in questions.

The untouched source is stored under ignored `private-data/imports/company-fields.original.json`. Contact/company examples are omitted from the distributable draft. Attio mappings are metadata only and do not enable synchronization or writes.

## Official references

- Decisions API: https://developers.openai.com/api/docs/guides/decisions
- API pricing: https://developers.openai.com/api/docs/pricing
- ChatGPT pricing: https://learn.chatgpt.com/docs/pricing

API-key requests use the API project's billing. Do not assume ChatGPT subscription credits are the same balance; this test reports authentication/quota failures without exposing credentials.
