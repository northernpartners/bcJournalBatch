# Business Central Journal Batch API

A custom unbound OData v4 action exposes a JSON endpoint that inserts General Journal lines into Business Central in sets, assigning one Document No. per set from the batch’s No. Series.

## Current version

Current version is M2.

- **Endpoint** (unbound action)
    - POST https://api.businesscentral.dynamics.com/v2.0/{tenant}/{environment}/ODataV4/JournalBatchHandler_PostJournalBatch?company={CompanyName}
    - Header alternative: Company: {CompanyName}
- **Auth:** AAD Bearer token
- **Service:** Codeunit 50101 Journal Batch Handler ([ServiceEnabled])
- **Template:** Fixed to BCINT
- **Batch**
    - If batchName provided → used.
    - If empty/missing → a batch is auto‑created (APIXXXXXXXX) under template BCINT.
    - The batch No. Series is set (or enforced) to BCINT.
- **Document numbering**
    - The app calls codeunit “No. Series” → GetNextNo on the batch’s No. Series.
    - One Document No. per set (lines = single set; lineSets = multiple sets).
- **Dimensions**
    - Supports CONTRACT and ACTPERIOD.
    - Accepts either a string or an object { code, name }:
        - contractCode: "DK-002182-KIN" or { "code": "DK-002182-KIN", "name": "Albert Messi" }
        - activityPeriod: "202508" or { "code": "202508", "name": "Aug 2025" }
    - Auto‑creates missing Dimension Values with provided name (if given).
    - If the Dimension Code (e.g., CONTRACT) is mapped to a Shortcut Dimension N (1..8) in General Ledger Setup, the line’s Shortcut Dimension field is set via ValidateShortcutDimCode(N, value) (so the visible “Contract Code”/“Activity period” columns populate). If not mapped, the value is merged into the line’s Dimension Set ID (posts correctly, but the specific column stays blank).
- **Validation behavior**
    - Standard Validate(...) on all mapped fields.
    - Per‑line insert uses [TryFunction]; errors are collected and returned without failing the whole request.
- **Out of scope in M2**
    - Posting (Gen. Jnl.-Post), idempotency, dimension hierarchies, VAT/currency logic beyond direct field mapping, preview mode, permissionset packaging.

## JSON payload (accepted input)

Top-level keys:
- `batchName` (string, optional) – journal batch under BCINT; auto-created if omitted/empty.
- `lines` (array) – single set of lines (backward compatible).
- `lineSets` (array) – multiple sets; each set has { "lines": [...] }.

Line fields (supported):
- `documentType` (string) – e.g., Payment, Invoice, Credit Memo, Refund.
- `documentDate` (date YYYY-MM-DD)
- `postingDate` (date YYYY-MM-DD)
- `externalDocumentNumber` (string) (alias: externalDocumentNo)
- `accountType` (string) – G_L_Account, Customer, Vendor, Bank_Account, Fixed_Asset, IC_Partner, Employee
- `accountNo` (string)
- `balanceAccountType` (string) (alias: balAccountType)
- `balanceAccountNumber` (string) (alias: balAccountNo)
- `currencyCode` (string)
- `amount` (number)
- `description` (string)
- Dimensions
    - `contractCode`: string or { "code": string, "name": string }
    - `activityPeriod`: string or { "code": string, "name": string }

> OData action takes a single string parameter named requestBody.
> Send your JSON payload stringified inside { "requestBody": "<string>" }.

## Example response

```json
{
  "success": true,
  "batchName": "API280C8B4",
  "sets": [
    {
      "success": true,
      "documentNo": "BCINT000123",
      "insertedCount": 1,
      "failedCount": 0,
      "failedLines": []
    },
    {
      "success": true,
      "documentNo": "BCINT000124",
      "insertedCount": 1,
      "failedCount": 0,
      "failedLines": []
    }
  ],
  "totalInserted": 2,
  "totalFailed": 0
}
```

> On validation issues (per-line), the corresponding set returns failedCount > 0 and a failedLines array with { index, error } entries; other sets continue unaffected.

## Setup

- Ensure No. Series `BCINT` exists and is valid; the app sets each auto-created batch to use it.
- For dimensions to appear in the visible line columns (not just in the dimension set), map `CONTRACT` and `ACTPERIOD` to Shortcut Dimensions in General Ledger Setup.

## Build & deploy

1. Update app.json version.
2.	Build: AL: Package → ./.alpackages/JournalBatch_<version>.app.
3.	Deploy: Extension Management → Upload → Install.
4.	Verify: $metadata contains JournalBatchHandler_PostJournalBatch.
5.	Test with Postman (company name or id).


## Codeunit overview

- **50101** Journal Batch Handler (ServiceEnabled)
    - Responsibility: parse payload, orchestrate flow, build response.
    - Keeps: PostJournalBatch, minimal glue logic only.

- **50102** JB Core

    - Responsibility: iterate sets/lines; call builders; collect errors; summarize.

- **50103** JB Line Builder

    - Responsibility: build & insert a single Gen. Journal Line from a JsonObject; field validations; mappings (MapAccountType, MapDocumentType).
    - Pattern: expose a public wrapper that calls a private [TryFunction] to catch validation errors and return true/false + GetLastErrorText().

- **50104** JB Batch Helpers

    - Responsibility: ensure template/batch; assign/verify No. Series; GetNextDocumentNo; GetNextLineNo.

- **50105** JB Dimension Helpers

    - Responsibility: ensure dim values exist (CONTRACT, ACTPERIOD), compute/merge Dimension Set ID, apply to line.

## Troubleshooting

- **404 Not Found** when calling action
    - App not installed, codeunit not published as web service, wrong company route, or wrong environment/tenant. Confirm action appears in $metadata under JournalBatchHandler_PostJournalBatch.
- **400 Bad Request**: Supported MIME type not found
    - Ensure Content-Type: application/json and that body shape is { "requestBody": "<stringified-json>" }.
- **“Journal Batch Name … DEFAULT cannot be found”**
    - M2 auto‑creates batch if batchName empty; ensure BCINT No. Series exists.
- **Dimensions not visible** on line
    - Ensure CONTRACT/ACTPERIOD are mapped to Shortcut Dimension 1/2 in General Ledger Setup; otherwise they’ll be in the Dimension Set but not in visible columns.

## Version milestones (future releases)

### M3 — Posting (per set)

Goal: When post=true, post each lineSet (one Document No. per set) via standard posting.
- AL changes
- Add post (bool) at top-level or per set (default false).
- After inserting a set’s lines (same Document No.), run posting:
- Filter Gen. Journal Line by Template = BCINT, Batch = <batchName>, Document No. = <DocNo>
- Call Codeunit "Gen. Jnl.-Post" RunWithCheck(GenJnlLine).
- Add result fields per set: posted (bool), postErrors (array), entryNoStart/entryNoEnd (optional, if you want to return G/L Entry range).
- Acceptance
- With valid lines and post=true: journal is empty afterwards, entries posted, response has posted=true.
- With validation error: posted=false and detailed errors, no partial posting.

---

### M4 — Idempotency & duplicate protection

Goal: Prevent duplicate inserts/posting on retries.
- AL changes
- Add optional batchId (client-provided unique string) at top-level or per set (setId).
- New table 50110 "API Batch Ledger" with fields: TemplateName, BatchName, SetId/BatchId, Document No., InsertedAt, Posted (Bool), Hash (Text).
- On receive:
- If batchId/setId already processed → return previous result, do not reinsert/repost.
- Store outcome after success (and optionally after failure with Posted=false).
- Acceptance
- Two identical calls with same batchId → second call is a fast no-op with same documentNo/status.

---

### M5 — Validation polish & mapping hardening

Goal: Fewer runtime surprises.
- AL changes
- Validate required fields (accountType, accountNo, amount).
- Enforce allowed enum values for accountType/balAccountType.
- Better date parsing (support YYYY-MM-DD and BC formats).
- Optionally default postingDate to WorkDate() if missing.
- Acceptance
- Clear error messages per line; unknown enums mapped or rejected consistently.

---

### M6 — Dimensions & External Doc No.

Goal: Real-world posting data.
- AL changes
- Top-level defaultDimensions and per-line dimensions (array of {code, value} or {dimCode, dimValue}).
- Apply via "Dimension Set ID" helpers (DimMgt / GetDimensionSetID patterns).
- Already supported externalDocumentNo—ensure it flows through posting.
- Acceptance
- Dimensions visible on posted entries; rejects invalid dimension codes/values with per-line errors.

---

### M7 — Currency, VAT, and balancing behavior

Goal: Handle typical financial scenarios.
- AL changes
- Optional currencyCode, vatBusPostingGroup, vatProdPostingGroup.
- Auto-balance set: if balAccount* not provided, allow a calculated balancing line (config flag autoBalance).
- Validate sum≈0 per set when autoBalance=false.
- Acceptance
- Multi-currency posting works when currency is set on batch/lines; VAT groups validate.

---

### M8 — Preview & Diagnostics

Goal: Dry-run and better insight.
- AL changes
- preview=true skips insert/post; runs validations and returns a simulated summary.
- Add diagnostics block in response (optional): timings, series used, line numbers assigned.
- Acceptance
- Preview returns what would happen, with zero DB changes.

---

### M9 — Security & Permissions

Goal: Correct least-privilege runtime.
- AL changes
- Add permissionset 50120 JournalBatchPerms with read/write on Gen. Journal Line, Gen. Journal Batch, Gen. Journal Template, posting codeunits, No. Series tables.
- Optionally a second set for posting (split insert vs post rights).
- Acceptance
- Installing app grants the set; endpoint fails cleanly if caller lacks permissions.

---

### M10 — Contract cleanup (post-GA nicety)

Goal: Eliminate “JSON-in-a-string” awkwardness.
- AL changes
- Define proper AL interface types for OData (records/complex types) or switch to a bound action on a small API page that takes native types.
- Maintain backward compatibility for a deprecation window.
- Acceptance
- Clients can POST normal JSON without double-escaping; old shape still supported until flag day.