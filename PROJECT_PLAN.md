# Real-time Scorecard 2: implementation plan

Status: planning complete with recommended defaults; API connection-test scaffold implemented. Native app implementation and paid API validation have not started. Deadline: October 10, 2026, 08:00 America/Los_Angeles. The user moved this earlier on October 9; OVERNIGHT_PLAN.md governs the overnight sequence and preflight findings. This is a target, not a completion guarantee.

## Supplied criteria catalog

The user supplied `company-fields.json` on October 9. Its 39 fields across four groups are now the starting catalog in `configurations/company-scorecard.draft.json`. This draft preserves all source IDs and adds exact team size and hosting provider, for 41 fields within the 50-field limit. It supersedes the older 21-field list as the configuration-design starting point; the original 21-field app remains useful for the first integration test. The draft is not yet loaded by the app or API test script.

The six source multi-select fields use one primary displayed answer in v1, consistent with the earlier user decision. CRM storage descriptions remain inert metadata. Original examples are retained only in the ignored `private-data/imports/company-fields.original.json`, not the distributable draft. Source document notes do not authorize CRM writes, hiding, or merging records.

Exact team size replaces the employee-range bucket in the default visible layout. The company-level hosting summary remains a hidden reference mapping; hosting environment and provider are visible. Administrative fields are manual-only, with hidden/combined-into kept out of the live scorecard. These are recommended draft defaults, not implemented UI behavior.

Remaining catalog gaps include individual/business return counts, staff role counts, revenue, and per-return pricing discussed earlier; these should be reconciled with the user's upcoming criteria description rather than inferred from unrelated deal amounts. Preserve `GruntWorks` as supplied pending reconciliation with the earlier `GruntWorx` spelling. Two hosting taxonomies in the source require an explicit mapping before any future CRM export. A mention of a competitor must not automatically become a loss reason or a completed deal stage.

## Outcome and release priorities

A native Mac sales assistant reads live transcript updates, maintains individual company facts, and displays them in a narrow, resizable scorecard. At least 95% of qualifying updates should appear within five seconds after the relevant sentence ends. No overall fit score. Inference uses cloud APIs; transcription uses OpenAI cloud audio by default; retain existing Apple Speech only as an explicit user-selectable option. ElevenLabs is excluded. Each user supplies their own credentials.

The deadline release prioritizes correct extraction, manual locks, saved answers, configurable criteria, the existing capture/calendar flow, and a reproducible downloadable build. Complete the milestones in order; optional work cannot consume the final release-validation window. Preserve requested features in the backlog if they miss the deadline, and state exactly what is missing. Do not silently call a partial build complete.

## Existing code and workspace

- Prior app: `/Users/rossgates/AI/codex-migration/projects/live-call-scorecard-2`.
- Independent new project: `/Users/rossgates/code/real-time-scorecard-2`.
- Reuse reviewed Swift/SwiftUI source, capture, transcript, calendar, and SQLite components. Copy only source/resources needed for this app, never the parent repository, live databases, credentials, or call exports.
- Prior package targets macOS 26 and Swift tools 6.2. Verify installed toolchain and supported hardware in milestone 1. Keep that baseline for the deadline unless a lower target is proven feasible.
- Use a separate bundle identifier and data directory. No existing data migration required. New call history persists across launches.
- Existing code uses hardcoded fields, local FoundationModels extraction, email-based identity, and automatic call export/push. Those need explicit replacement for the new design.

## Components and contracts

### 1. Credentials and connections

Native Settings/Admin is the admin portal for v1; no hosted admin service. OpenAI has masked key entry, save/remove, and connection status. A Test connection action sends synthetic input, displays success/error and request time, and never prints credentials. Use macOS Keychain in packaged builds; support ignored `.env` for development. The packaged app must not depend on the developer's source directory or shell environment. Distribute `.env.example`, never `.env` or a key. Runtime credentials and criteria exports are separate.

### 2. Configuration engine

Versioned JSON drives field IDs, labels, sections, order, types, canonical options, aliases, source policies, confidence presets, formulas, and initial/demo/review layouts. Maximum 50 fields; use the supplied 41-field draft catalog, with its 33 automatically extracted fields. The existing 21-field enum is a migration reference, not the final catalog. Maintain stable IDs independently of labels. JSON import validates atomically; invalid configurations leave the current one intact. Save multiple named configurations and switch the active one. Editing Settings changes the selected configuration and supports JSON export. A configuration revision accompanies every extraction job.

Removed fields/options remain in the database but are hidden and no longer evaluated. Mid-call configuration changes apply immediately; results from an obsolete configuration cannot overwrite new state. Corrections can suggest aliases, stored against a particular field and canonical option; no cross-company or provider training. Canonical names take priority over transcript spelling. `Other: <value>` retains unlisted products without extending the enum silently.

Seed fields: name, firmName, location, timezone, totalReturns, personalReturns, businessReturns, primaryTaxSoftware, taxSoftwareEnvironment, taxSoftwareHost, clientPortal, practiceManagement, supportingSoftware, admins, preparers, reviewers, cpas, annualCommitment, pilotCommitment, otherNumbers, notes. Retain old persisted identifiers where useful. The user's criteria rant can refine these meanings and options later; provisional defaults must be labeled, especially software/competitor spellings.

One answer per field. Multi-package displays and primary-package modeling are deferred. Notes can hold concise text, but enum fields must resolve to one canonical option or Other. Numeric ranges display their midpoint and preserve the spoken range in evidence. Counts display integer midpoints using a documented rounding rule; money retains currency and precision. Derive business = total minus personal, total = personal plus business, or personal = total minus business only when inputs are sufficient and consistent. Never invent the breakdown between business return types. Negative or inconsistent results become conflicts. Calculations obey locks and carry links to their input evidence.

### 3. Transcript ingestion and scheduling

Adapt existing stable segment IDs, speaker roles, finalization state, and timestamps. Treat finalized segments as the authoritative stream; coalesce nearby events for approximately 250 ms as a starting point. Keep a recent bounded context window plus existing company state, and retrieve older relevant evidence when needed. Do not repeatedly send the full 45-minute transcript.

Every job includes company ID, call ID, segment revisions, config revision, and field versions. Deduplicate segment events. Bound concurrency and queue size. Cancel or discard superseded work without losing evidence. Timestamp sentence end, finalized transcript, request start/end, reducer commit, and visible UI render. Measure five-second latency from sentence end, including transcription delay; a transcript-only benchmark is reported separately.

Capture continues locally during network outages. Persist queued work and catch up after reconnect without moving results into a different customer/call. Delayed updates may apply only if still relevant. Finish pending analysis after End call; show pending/complete status. Queue state survives relaunch. A user-selected Debrief mode permits salesperson dictation to populate prospect-only fields after a call; never infer that the prospect has left merely from silence.

### 4. Cloud extraction

Use OpenAI Decisions with `gpt-6-luna` for fixed choices and criterion relevance. Batch independent questions over shared context. The app owns memory and scheduling; the API does not continuously monitor the transcript by itself. Validate API access early and benchmark 21 and 50 fields before choosing batch sizes.

Use structured extraction through OpenAI Responses for names, numbers, notes, Other details, and exact evidence references. Select and pin a supported economical model during the first benchmark; no automatic model shopping or provider switching. Run independent work concurrently; deeper extraction only for relevant fields. If a detector misses facts, broaden its gate or remove the extra stage for affected fields. Optimize against measured accuracy/latency/cost rather than assuming two API stages are always faster.

Reject malformed results, invalid enum values, unsupported evidence IDs, incorrect units, and quotes absent from the cited segment. Treat transcript instructions as untrusted conversation data. Speaker source policies apply before committing updates. Prospective values never write directly into the database or UI; all pass through the reducer.

### 5. Fact reducer and company storage

SQLite stores companies, contacts, calls, transcript segments, configurations, current facts, evidence, pending jobs, proposals, and immutable change events. Firm-level current facts are the source of truth. Historical call views show current company answers; evidence and the change ledger preserve when each answer actually changed. Editing from any call updates company truth everywhere. Different contacts at the same company inherit company facts. The person-name field refers to the current contact, avoiding overwriting a firm with an unrelated person's identity.

Calendar proposes firm identity; auto-select only an unambiguous match. Otherwise offer an inline selector/name in the first row. Do not merge firms solely on common email domains. Customer answers never expire. Locks and section-collapse preferences persist by company. Configurations use explicit field namespaces to prevent two companies' unrelated schemas sharing facts accidentally.

Unlocked fields update automatically. Starting tunable confidence presets: tentative 0.55, confident initial fill 0.75, replacement 0.90; replacement also requires materially new evidence and a clear advantage over alternatives. These are experimental model thresholds, not calibrated accuracy percentages. Below tentative threshold show only a yellow question mark. Tentative answers show red text with an accessible low-confidence description. Avoid flipping on repeated copies of the same evidence. Strong explicit corrections may replace previous answers once validation passes.

Manual edits lock automatically; users can edit locked fields again. AI and derived formulas cannot overwrite locks. Contradictory evidence creates a proposed replacement with `!` and an info control. Accepting a proposal is one action and leaves the field locked. Dismissing records the decision. Clearing a field sets an evidence watermark so old transcript replay cannot immediately repopulate it. Undo restores the previous value and lock state; retain the correction history.

### 6. Live scorecard UI

Preserve approved black background, small monospaced type, green accents, and narrow full-height starting footprint. Make the window resizable. All fields remain accessible through scrolling; sections collapse manually and never auto-expand on updates. Distinct changed-field counts accumulate while collapsed and clear when opened. Locked proposals show a separate subtle `!`, without pretending the locked value changed.

Unknown and needs-detail states show only yellow `?`. Evidence is always behind `+` until explicitly opened. Use a small row-start source dot: green call, yellow calendar, blue email, with accessible labels/tooltips; reserve distinct manual/calculated markers. Email color is supported in the data model but does not imply an email connector exists. Source indicators remain visible on all populated facts.

Values stay one line; hover/focus disclosure shows the full value. Briefly highlight changed visible values without moving row order. Bottom transcript preview is hidden; full transcript remains available. No suggested follow-up questions, overall score, or font-size controls in v1. Section/field order is edited in Settings and varies by call type. Preserve transparency and sharing-exclusion preference, enabled by default.

Keyboard defaults: arrows navigate when outside text editing, Return edits/commits, Escape cancels, Command-Shift-L toggles lock, Command-Z and Control-Z undo, Command-F finds fields. Allow customization with conflict detection. During text editing arrows and select-all retain normal text behavior. Protect system/global shortcuts. Verify sharing exclusion in the actual Google Meet capture modes used; an OS window preference alone is not proof it is hidden.

### 7. Evaluation and diagnostics

Build a labeled synthetic replay suite before using private calls. Cover software aliases, ambiguous hosting, salesperson questions versus customer assertions, denials, corrections, midpoints, formulas, locks, duplicate/revised segments, old responses, multiple companies, config switches, offline recovery, and debrief. Add real calls only when specifically designated for testing; corrections remain local evaluation data.

Recommended release gates: at least 95% precision of committed answers, at least 90% recall of answerable labeled fields, zero automatic locked-field overwrites, zero cross-company writes, and p95 sentence-to-visible update at or below five seconds. Report sample size and per-field results; a small synthetic pass is not a real-world accuracy guarantee. Run at least one 45-minute replay and two live end-to-end trials where available, including Meet screen sharing and audio. If real-call validation requires Ross, leave that gate pending rather than marking it passed.

Track token/request usage, queue lag, latency distribution, and estimated cost in Settings. Proposed operating target: less than $1 per meeting-hour for extraction, measured rather than promised; transcription reported separately. Configure user budgets and warning thresholds. No arbitrary paid benchmarking loops; each automated smoke check makes one bounded synthetic request. Use a conservative $5 maximum estimated API-test spend for the overnight run, with bounded requests and a usage ledger; this is a self-imposed ceiling, not permission to purchase credits. A quota failure stops repeated paid calls to that endpoint while offline implementation continues. No purchase, auto-recharge, or subscription changes.

### 8. Retention and distribution

Keep company answers and their change ledger until customer deletion. Default raw transcript retention: 30 days, configurable; retain evidence excerpts supporting current answers unless deleted. Customer deletion removes associated transcripts, answers, evidence, proposals, and pending local jobs. Explain that provider-held processing records follow provider policies; do not claim local deletion removes those records.

No multi-computer sync, hosted shared database, CRM/email ingestion, or provider-training opt-in in the deadline release. Many people can independently install and use the app with their own keys and local data. Export criteria JSON and user-requested company JSON. Disable the inherited automatic transcript-to-GitHub publication path. Public releases contain synthetic examples only.

Target a public source repository with a license (recommend MIT after checking inherited code ownership/licensing), build instructions, `.env.example`, default configuration, test suite, and release notes. Package a ZIP or DMG on GitHub Releases with checksums. Sign/notarize only if appropriate credentials and distribution rights are available; otherwise clearly label unsigned distribution and document standard macOS opening steps without disabling Gatekeeper globally. Do not claim a clean install until tested. Confirm destination repository before publishing if it cannot be established from the project context.

## Milestones and acceptance gates

| Milestone | Deliverable | Gate before proceeding |
|---|---|---|
| 0. Plan and key setup | This plan, private key file, synthetic Decisions test | Offline harness checks pass; user can enter key; live access remains pending until key exists |
| 1. Accurate cloud vertical slice | Independent Swift app baseline, Settings key entry, Decisions + structured extraction, transcript replay into existing fields | Correct enum/numeric/evidence results on representative replay; measured API access/latency; no local LLM extraction |
| 2. JSON and company state | Dynamic supplied catalog with 50-field limit, saved configs, firm identity, SQLite truth, locks/proposals/undo | Config validation and switching; persistence after relaunch; lock/stale-response/cross-company tests pass |
| 3. Approved live UI | Collapsible sections, counts, source dots, confidence styling, evidence disclosure, editing, resize, call layouts | Visual review against approved mockups; long answers and keyboard behavior verified; no automatic expansion |
| 4. Live call integration | Existing audio/transcription/calendar/history, queues, post-call drain/debrief, OpenAI cloud transcription adapter | End-to-end trial, reconnect/restart tests, 45-minute replay; sentence-to-render p95 measured; Meet audio and sharing checked |
| 5. Hackathon release | Buildable open-source package and downloadable Mac binary | Clean build/install, credential/data scan, license check, documented feature/gate status, release artifact verified |
| 6. Post-deadline improvements | Alias learning refinement, full settings editor/shortcut customization if deferred, advanced diagnostics and larger real-call evaluation | Regression suite remains green; changes justified by observed misses |

Dependency chain: 0 → 1 → 2 → 3 → 4 → 5. UI may be prepared alongside extraction within the same implementation effort, but passing UI checks cannot substitute for extraction quality. Reserve the final 60–90 minutes before 08:00 for packaging, clean launch, and submission checks. If time runs short, first defer rich configuration editing (keep JSON import/export), learned aliases, and shortcut customization. Record each deferral explicitly. Never defer key isolation, lock correctness, truthful extraction status, or basic persistence.

## Recommended defaults for unanswered questions

Finish pending work after calls; OpenAI extraction and cloud transcription; no ElevenLabs; independent user keys; fixed benchmarked pipeline; no silent fallback provider or local extraction; local-only storage; explicit user-started exports; local correction evaluation only; no fine-tuning. Use synthetic tests until permitted real examples are available. Human review is needed for final live-call comfort and visibility, not each internal milestone. Continue automatically through passing build/test milestones; pause only for an actual credential, spending, publishing, permission, or product blocker. Do not treat a deadline or exhausted allowance as evidence of completion.

## Future implementation-goal prompt

Build Real-time Scorecard 2 using this PROJECT_PLAN.md and the approved mockups. Work through milestones 1–5, preserving the old app and user data. Use the existing Swift source as the starting point and the new workspace as the independent project. Use OpenAI Decisions for classification and an economical supported OpenAI structured extractor for freeform fields; keep local LLM extraction disabled. Implement native Settings key entry and never expose or publish keys. Complete appropriate automated checks after each milestone and report completed/pending gates in a progress file. Target a working, installable hackathon release by October 10, 2026 at 08:00 Pacific; defer only the documented optional features if necessary and disclose them. Do not mark the goal complete until implemented scope, test evidence, and distributable artifacts are verified. Ask only for genuine blockers, including missing credentials, an unresolved publication destination. Use OVERNIGHT_PLAN.md and the goal created for this chat as the current execution instructions. A document alone is not a running job.

## References

OpenAI Decisions: https://developers.openai.com/api/docs/guides/decisions

OpenAI structured outputs: https://developers.openai.com/api/docs/guides/structured-outputs

Current test harness only exercises fixed choices. Native integration, all-field extraction, live latency, API cost, OpenAI audio access, signing, and release availability must be validated during implementation.
