# Architecture

The app is a native SwiftUI overlay. It uses macOS frameworks for audio capture, Keychain for credentials, SQLite for local state, and cloud OpenAI APIs for inference.

```mermaid
flowchart LR
  A[Microphone · salesperson] --> T[OpenAI transcription]
  B[Selected browser · customer] --> U[OpenAI transcription]
  T --> Q[Durable transcript queue]
  U --> Q
  R[Synthetic replay or debrief] --> Q
  Q --> D[Decisions · canonical choices]
  Q --> E[Responses · values and evidence]
  D --> V[Validation and fact reducer]
  E --> V
  V --> C[Supported numeric calculations]
  C --> S[SQLite company truth and change history]
  S --> UI[SwiftUI scorecard]
  J[Versioned criteria JSON] --> D
  J --> E
  J --> UI
```

## Commit rules

Every extraction job carries company/call identity, configuration revision, transcript revisions, and field versions. The main-actor reducer checks those again after network calls return. Manual edits can proceed during requests; a late response cannot undo them. Locks protect values from inference and arithmetic. Conflicts become proposals; accepting a proposal retains the lock. Contradictory direct numeric inputs remain intact and show a calculation-conflict explanation; invalid negative derived values are never displayed.

Evidence quotes must occur in the referenced final transcript segment. Fixed choices ordinarily require agreement between Decisions and structured extraction. Up to four high-confidence extracted fields that fail classification may receive one focused Decisions recheck. The same quote, speaker, configuration, version and lock guards still apply; there is no recursive classification retry.

A field may explicitly opt into `allow_tentative_named_other`. For an unlisted name occurring verbatim in the supporting quote, a high-confidence structured extraction can supply a provisional Other value despite classifier disagreement or low confidence. The displayed confidence is capped at the field's tentative threshold, so it stays red. This path only fills an empty, unlocked field from direct customer speech or explicit debrief, never an existing answer. It cannot turn a listed option/alias into Other or bypass a refused, missing or invalid classifier answer. This is a heuristic provisional policy, not a calibrated probability. Explicitly named values outside the supplied catalog use Other with a detail. Unknown stays null. New replies that contradict a filled answer require the replacement threshold. Thresholds are tunable heuristics, not calibrated probabilities.

Company truth is shared across that company's calls within a configuration namespace. Old fields and configurations stay stored when a catalog changes. A switch atomically supersedes pending jobs and reprocesses this call against the selected catalog. A generation check discards late results from the old configuration.

## Audio and recovery

Capture begins only after an explicit Start. Microphone and selected-browser audio use independent streams to distinguish salesperson from customer. PCM is converted to mono 24 kHz; a lightweight energy detector creates bounded speech chunks. The default is OpenAI cloud transcription. Apple Speech is opt-in; there is no local LLM or silent provider fallback.

Each cloud channel retains at most 12 unfinished audio turns in memory. It can reconnect twice after a network failure, resend those turns with the original client IDs, and ignore late replies from the previous connection. Quota, authentication, invalid protocol, and budget failures stop automatically. Final drain is bounded to eight seconds; missing audio is reported. Raw audio is not persisted for crash recovery. Final transcript jobs are durable and can resume from History.

Extraction is serial per call, with concurrent Decisions/Responses requests and up to four queued sentences coalesced into one job. At most 128 pending jobs are loaded into the active page; overflow stays in SQLite and recovery follows transcript sequence. Transient text failures allow at most three attempts per durable job. Quota, authentication, budget, and rate-limit failures require an explicit retry.

## Measurement

Replay arrivals use fixed clock deadlines independent of API response timing. Reports distinguish queue delay, processing time, and sentence-arrival-to-database-commit latency. A separate distribution covers batches that committed updates. The native UI records visible-row update callbacks, which are not physical display scan-out measurements. A real Meet audio-to-screen trial is still required for that end-to-end claim.

A persisted ledger estimates text cost from returned usage and reserves audio cost before upload, including retransmitted audio. Settings shows the estimate and a cumulative local allowance. This protects local requests; it does not change OpenAI account billing or purchase credits.
