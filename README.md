# Business Central Journal Batch API

## Codeunits

- 50101 Journal Batch Handler (ServiceEnabled)
Responsibility: parse payload, orchestrate flow, build response.
Keeps: PostJournalBatch, minimal glue logic only.
- 50102 JB Core
Responsibility: iterate sets/lines; call builders; collect errors; summarize.
- 50103 JB Line Builder
Responsibility: build & insert a single Gen. Journal Line from a JsonObject; field validations; mappings (MapAccountType, MapDocumentType).
Pattern: expose a public wrapper that calls a private [TryFunction] to catch validation errors and return true/false + GetLastErrorText().
- 50104 JB Batch Helpers
Responsibility: ensure template/batch; assign/verify No. Series; GetNextDocumentNo; GetNextLineNo.
- 50105 JB Dimension Helpers
Responsibility: ensure dim values exist (CONTRACT, ACTPERIOD), compute/merge Dimension Set ID, apply to line.

## Version

Current version is M2

## Milestones

### M3 — Posting (per set)

Goal: When post=true, post each lineSet (one Document No. per set) via standard posting.
	•	AL changes
	•	Add post (bool) at top-level or per set (default false).
	•	After inserting a set’s lines (same Document No.), run posting:
	•	Filter Gen. Journal Line by Template = BCINT, Batch = <batchName>, Document No. = <DocNo>
	•	Call Codeunit "Gen. Jnl.-Post" RunWithCheck(GenJnlLine).
	•	Add result fields per set: posted (bool), postErrors (array), entryNoStart/entryNoEnd (optional, if you want to return G/L Entry range).
	•	Acceptance
	•	With valid lines and post=true: journal is empty afterwards, entries posted, response has posted=true.
	•	With validation error: posted=false and detailed errors, no partial posting.

⸻

### M4 — Idempotency & duplicate protection

Goal: Prevent duplicate inserts/posting on retries.
	•	AL changes
	•	Add optional batchId (client-provided unique string) at top-level or per set (setId).
	•	New table 50110 "API Batch Ledger" with fields: TemplateName, BatchName, SetId/BatchId, Document No., InsertedAt, Posted (Bool), Hash (Text).
	•	On receive:
	•	If batchId/setId already processed → return previous result, do not reinsert/repost.
	•	Store outcome after success (and optionally after failure with Posted=false).
	•	Acceptance
	•	Two identical calls with same batchId → second call is a fast no-op with same documentNo/status.

⸻

### M5 — Validation polish & mapping hardening

Goal: Fewer runtime surprises.
	•	AL changes
	•	Validate required fields (accountType, accountNo, amount).
	•	Enforce allowed enum values for accountType/balAccountType.
	•	Better date parsing (support YYYY-MM-DD and BC formats).
	•	Optionally default postingDate to WorkDate() if missing.
	•	Acceptance
	•	Clear error messages per line; unknown enums mapped or rejected consistently.

⸻

### M6 — Dimensions & External Doc No.

Goal: Real-world posting data.
	•	AL changes
	•	Top-level defaultDimensions and per-line dimensions (array of {code, value} or {dimCode, dimValue}).
	•	Apply via "Dimension Set ID" helpers (DimMgt / GetDimensionSetID patterns).
	•	Already supported externalDocumentNo—ensure it flows through posting.
	•	Acceptance
	•	Dimensions visible on posted entries; rejects invalid dimension codes/values with per-line errors.

⸻

### M7 — Currency, VAT, and balancing behavior

Goal: Handle typical financial scenarios.
	•	AL changes
	•	Optional currencyCode, vatBusPostingGroup, vatProdPostingGroup.
	•	Auto-balance set: if balAccount* not provided, allow a calculated balancing line (config flag autoBalance).
	•	Validate sum≈0 per set when autoBalance=false.
	•	Acceptance
	•	Multi-currency posting works when currency is set on batch/lines; VAT groups validate.

⸻

### M8 — Preview & Diagnostics

Goal: Dry-run and better insight.
	•	AL changes
	•	preview=true skips insert/post; runs validations and returns a simulated summary.
	•	Add diagnostics block in response (optional): timings, series used, line numbers assigned.
	•	Acceptance
	•	Preview returns what would happen, with zero DB changes.

⸻

### M9 — Security & Permissions

Goal: Correct least-privilege runtime.
	•	AL changes
	•	Add permissionset 50120 JournalBatchPerms with read/write on Gen. Journal Line, Gen. Journal Batch, Gen. Journal Template, posting codeunits, No. Series tables.
	•	Optionally a second set for posting (split insert vs post rights).
	•	Acceptance
	•	Installing app grants the set; endpoint fails cleanly if caller lacks permissions.

⸻

### M10 — Contract cleanup (post-GA nicety)

Goal: Eliminate “JSON-in-a-string” awkwardness.
	•	AL changes
	•	Define proper AL interface types for OData (records/complex types) or switch to a bound action on a small API page that takes native types.
	•	Maintain backward compatibility for a deprecation window.
	•	Acceptance
	•	Clients can POST normal JSON without double-escaping; old shape still supported until flag day.