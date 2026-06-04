# Agentforce POC — Design Document

**Project:** Agentforce Proof of Concept  
**Platform:** Salesforce (API v64.0)  
**Last Updated:** 2026-06-02  
**Status:** Active development — US-009, US-010, US-011 on feature branches; US-001–US-007 merged to main

---

## 1. Purpose & Scope

This project demonstrates an AI-augmented submission intake pipeline for commercial insurance (Workers' Compensation focus). The system captures inbound broker emails, converts them into structured Submission records, uses Agentforce (Salesforce's native LLM service) to extract key data from attached documents, validates submission completeness, drafts broker follow-up emails, and scores submissions against underwriting appetite — all within Salesforce.

The POC covers the first four stages of an underwriting workflow:

1. **Receive** — Capture broker email + attachments into Salesforce
2. **Process** — Promote email to a Submission record
3. **Extract** — Parse structured data from documents using AI
4. **Triage** — Validate completeness, detect risks, match against appetite

---

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│  INBOUND EMAIL  (Broker → Email-to-Salesforce address)              │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
               SubmissionEmailHandler (global)
                           │
              ┌────────────┴────────────┐
              │                         │
  SubmissionEmailService     SubmissionFileService
  Creates Submission_Email__c  Stores attachments as
  with metadata & body         ContentVersion (Files)
              │                         │
              └────────────┬────────────┘
                           │
                  Submission_Email__c
                  Status: "Received"
                           │
         ┌─────────────────┼──────────────────┐
         │                                    │
  submissionsInbox LWC               (Future: Agentforce
  "Process" button                    autonomous agent)
         │
  ProcessSubmissionEmailAction
  - Creates Submission__c
  - Re-links attachments
  - Sets email status → "Processed"
         │
  Submission__c
         │
  ┌──────┴─────────────────────────────────────────┐
  │                    │                           │
  submissionExtractButton LWC          submissionFollowUpEmail LWC
  SubmissionExtractionAction           SubmissionValidationAction
  - PDF.co text extraction             - Rules-based completeness check
  - Agentforce prompt template         - Agentforce follow-up email draft
  - Maps JSON → Submission fields      - Creates Missing_Item__c records
         │                                         │
  Extracted Data fields                   submissionRiskSignals LWC
  (Insured, Policy dates,                 RiskSignalService
   NAICS, Payroll, etc.)                  - Rules engine (metadata-driven)
                                          - MockRiskApiService (external scores)
                                          - Agentforce underwriter brief
                                          - Creates Submission_Risk_Signal__c records
```

---

## 3. Custom Data Model

### 3.1 Object Relationship Diagram

```
Submission_Email__c ──(lookup)──► Submission__c
                                        │
                              ┌─────────┼──────────────┐
                              │         │              │
                     WC_Class_Location__c  Missing_Item__c  Submission_Risk_Signal__c
                     (Master-Detail)       (Master-Detail)  (Master-Detail)

Standalone objects (not yet integrated):
  Loss_Year__c
  Officer__c
```

### 3.2 Object Definitions

#### Submission_Email__c — Submission Email

The inbox record representing a raw inbound broker email.

| Field | Type | Description |
|---|---|---|
| Name | AutoNumber (SE-{0000000}) | System identifier |
| From_Name__c | Text(255) | Sender display name |
| From_Email__c | Text(255) | Sender email address |
| Subject__c | Text(255) | Email subject line |
| Body__c | LongTextArea(131072) | Full email body (plaintext preferred over HTML) |
| Received_Date__c | DateTime | Timestamp of receipt |
| Attachment_Count__c | Number | Count of binary + text attachments |
| Status__c | Picklist | Lifecycle status: Received / Processing / Processed / Failed |
| Processing_Log__c | LongTextArea | Debug/audit trail for processing steps |

**Lifecycle:** Received → Processing → Processed (or Failed)  
**Sharing:** ReadWrite (all users)

---

#### Submission__c — Submission

The core underwriting submission record. Created from a Submission_Email__c; enriched by AI extraction and validation.

| Field | Type | Description |
|---|---|---|
| Name | Text | Auto-generated: `YYYYMMDD-LastName-Submission` |
| Source__c | Text(255) | Origin channel, e.g. "Email" |
| Received_Date__c | DateTime | When the submission was received |
| Body__c | LongTextArea | Raw email body for reference |
| Submission_Email__c | Lookup → Submission_Email__c | Source email link |
| **Extracted fields (US-009)** | | |
| Insured_Name__c | Text | AI-extracted insured company name |
| Policy_Effective_Date__c | Date | AI-extracted coverage start date |
| Policy_Expiration_Date__c | Date | AI-extracted coverage end date |
| Requested_Coverage__c | Text | AI-extracted coverage type(s) |
| Payroll__c | Currency | AI-extracted total payroll |
| NAICS_Codes__c | LongTextArea | AI-extracted NAICS industry codes |
| Locations__c | LongTextArea | AI-extracted locations JSON |
| Broker_Name__c | Text | AI-extracted broker name |
| Extraction_Status__c | Picklist | Pending / In Progress / Completed / Failed |
| Extraction_Log__c | LongTextArea | AI extraction audit log |
| Extraction_JSON__c | LongTextArea | Raw JSON response from AI |
| Extraction_Confidence__c | Percent | AI confidence score for extraction |
| **Validation fields (US-010)** | | |
| Completeness_Status__c | Picklist | Incomplete / Needs Review / Complete |
| Follow_Up_Email_Draft__c | LongTextArea | AI-generated broker follow-up email |
| Line_of_Business__c | Picklist | Workers Comp / General Liability / etc. |
| Number_of_Employees__c | Number | Total employee count |
| **Risk fields (US-011)** | | |
| Risk_Score__c | Number | Aggregate risk score from rules + external API |
| Appetite_Score__c | Number | Underwriting appetite alignment score |
| Review_Priority__c | Picklist | Low / Medium / High |
| Risk_Summary__c | LongTextArea | AI-generated underwriter brief |

**Sharing:** ReadWrite

---

#### WC_Class_Location__c — WC Class Location

Represents a single Workers' Compensation class code at a specific location within a submission.

| Field | Type | Description |
|---|---|---|
| Name | AutoNumber (WCL-{0000000}) | System identifier |
| Submission__c | MasterDetail → Submission__c | Parent submission |
| Class_Code__c | Text | WC class code (e.g., "8810") |
| Class_Description__c | Text | Human-readable class description |
| Location_Number__c | Number | Location index within submission |
| Employee_Count__c | Number | Headcount for this class |
| Payroll__c | Currency | Annual payroll for this class |
| State__c | Text | Operating state |
| Appetite_Flag__c | Text | Underwriting appetite status for this class/state |

**Sharing:** ControlledByParent

---

#### Missing_Item__c — Missing Item (US-010)

Records a specific missing piece of information detected during submission validation.

| Field | Type | Description |
|---|---|---|
| Name | AutoNumber | System identifier |
| Submission__c | MasterDetail → Submission__c | Parent submission |
| Requirement_Type__c | Picklist | RequiredField / RequiredDocument / ConditionalField |
| Missing_Message__c | LongTextArea | Human-readable explanation of what is missing |
| Severity__c | Picklist | Critical / High / Medium / Low |
| Sort_Order__c | Number | Display order |
| Is_Resolved__c | Checkbox | Whether the issue has been resolved |

**Sharing:** ControlledByParent

---

#### Submission_Risk_Signal__c — Submission Risk Signal (US-011)

Records a specific risk indicator or appetite flag for a submission.

| Field | Type | Description |
|---|---|---|
| Name | AutoNumber | System identifier |
| Submission__c | MasterDetail → Submission__c | Parent submission |
| Signal_Type__c | Text | Type of risk signal (matches rule name) |
| Severity__c | Picklist | Critical / High / Medium / Low / Info |
| Score__c | Number | Numeric weight for this signal |
| Source__c | Picklist | Rules / ExternalAPI / Agentforce |
| Explanation__c | LongTextArea | Why this signal was raised |
| Recommended_Action__c | LongTextArea | Suggested underwriter response |

**Sharing:** ControlledByParent

---

#### Risk_Appetite_Rule__mdt — Risk Appetite Rule (Custom Metadata, US-011)

Configurable rules evaluated by `RiskSignalService`. Stored as custom metadata; no deployment needed to change rule values.

| Field | Type | Description |
|---|---|---|
| Label | Text | Rule display name |
| Rule_Type__c | Text | FieldThreshold / FieldBlank / FieldNotBlank / DocumentMissing / DocumentPresent |
| Field_API_Name__c | Text | Submission field to evaluate |
| Threshold_Value__c | Number | Threshold for FieldThreshold rules |
| Document_Keyword__c | Text | Keyword for document presence/absence rules |
| Severity__c | Text | Signal severity to raise |
| Signal_Type__c | Text | Signal type label |
| Message__c | Text | Explanation message |
| Recommended_Action__c | Text | Suggested action |
| Line_of_Business__c | Text | LOB filter (e.g., "Workers Comp") |
| Sort_Order__c | Number | Evaluation order |
| Active__c | Checkbox | Whether the rule is active |

**Seeded rules:** Workers Comp High Payroll, Missing Loss Runs, Missing NAICS, Multi-Location, Missing Safety Docs

---

#### Submission_Requirement__mdt — Submission Requirement (Custom Metadata, US-010)

Configurable completeness requirements evaluated by `SubmissionValidationAction`.

| Field | Type | Description |
|---|---|---|
| Label | Text | Requirement display name |
| Requirement_Type__c | Text | RequiredField / RequiredDocument / ConditionalField |
| Required_Field_API_Name__c | Text | Submission field to check |
| Document_Type__c | Text | Document keyword to check |
| Missing_Message__c | Text | Message if missing |
| Severity__c | Text | Critical / High / Medium / Low |
| Line_of_Business__c | Text | LOB filter |
| Sort_Order__c | Number | Evaluation order |
| Active__c | Checkbox | Whether active |

**Seeded rules:** Workers Comp Effective Date, Employees, Loss Runs, NAICS Codes, Payroll, Signed ACORD

---

#### Loss_Year__c, Officer__c, Risk_Signal__c

Three objects defined in the data model as scaffolding for future features. Not yet wired into active processing logic.

- **Loss_Year__c** — Historical loss data per policy year (claims, carrier, incurred losses)
- **Officer__c** — Business principals with include/exclude and ownership percentage
- **Risk_Signal__c** — (Original standalone signal object; superseded by Submission_Risk_Signal__c in US-011)

---

## 4. Features

### US-004 — Create Submission Business Object (SCRUM-4)

**Branch:** SCRUM-4-us-004 → merged main  
**What was built:**
- `Submission__c` custom object with core fields (Name, Source, Received_Date, Body, Submission_Email lookup)
- Page layout: Submission Layout (two-column header + Email Body section + Related Files)
- `Submission__c` tab

---

### SCRUM-10 — Create App for the Demo

**Branch:** SCRUM-10 → merged main  
**What was built:**
- `Agentforce_POC` Lightning app with sidebar navigation
- Three tabs: Submissions Inbox (custom page), Submission Email (standard), Submission (standard)
- Default landing tab set to Submissions Inbox

---

### US-005 — Receive Broker Email into Salesforce (SCRUM-5)

**Branch:** SCRUM-5-us-005 → merged main  
**What was built:**

**`SubmissionEmailHandler`** — global inbound email handler
- Implements `Messaging.InboundEmailHandler`
- Entry point for all broker emails arriving at the org's email service address
- Delegates to `SubmissionEmailService` (record creation) and `SubmissionFileService` (attachments)

**`SubmissionEmailService`** (`without sharing`)
- Parses raw `Messaging.InboundEmail` object
- Counts binary and text attachments
- Prefers plaintext body over HTML
- Inserts `Submission_Email__c` with Status = "Received"

**`SubmissionFileService`** (`without sharing`)
- Converts binary and text attachments to `ContentVersion` blobs
- Links each file to the parent email via `FirstPublishLocationId`
- Bulk inserts in a single DML statement

**`Submission_Email__c`** object, layout, and tab  
**`Agentforce_POC_Access`** permission set

---

### US-007 — Process Broker Email into Submission (SCRUM-7)

**Branch:** SCRUM-7-us-007 → merged main  
**What was built:**

**`ProcessSubmissionEmailAction`**
- Dual entry points:
  - `@InvocableMethod process(List<Input>)` — called by flows or Agentforce agents
  - `@AuraEnabled processEmail(String submissionEmailId)` — called by LWC buttons
- Core logic in `private static String doProcess(String emailId)`:
  1. Fetches `Submission_Email__c`
  2. Extracts sender last name; generates name `YYYYMMDD-LastName-Submission`
  3. Creates `Submission__c` linked to the email
  4. Queries `ContentDocumentLink` records on the email; re-links each to the new Submission with `ShareType='V'`, `Visibility='AllUsers'`
  5. Sets email `Status__c` = "Processed"

**`Process_Submission_Email`** AutoLaunchedFlow
- Wraps the invocable method for Agentforce and future automation
- Input: `submissionEmailId`; Output: `submissionId`

---

### US-006 — Submissions Inbox UI (SCRUM-6)

**Branch:** SCRUM-6-us-006 → merged main  
**What was built:**

**`SubmissionsInboxController`** (`with sharing`, `cacheable=true`)
- Returns up to 200 `Submission_Email__c` records ordered by `Received_Date__c DESC`
- Fields: Id, From_Name__c, From_Email__c, Subject__c, Received_Date__c, Attachment_Count__c, Status__c

**`submissionsInbox` LWC**
- Lightning datatable with columns: From, Subject, Received, Attachments, Status, Process
- Row click navigates to the `Submission_Email__c` record page
- Process button:
  - Calls `ProcessSubmissionEmailAction.processEmail()` imperatively
  - Shows spinner during execution
  - On success: success toast + refresh + navigate to new `Submission__c`
  - On failure: sticky error toast
  - Disabled if `Status__c === 'Processed'`
- Refresh button via `refreshApex()`

**`Submissions_Inbox_Page`** FlexiPage (AppPage, one-column, hosts the LWC)

---

### US-009 — Extract Structured Data from Submission Documents (SCRUM-11)

**Branch:** SCRUM-11-us-009 — **not yet merged to main**  
**What was built:**

**12 new `Submission__c` fields** for extracted data (see data model above)

**`PDFcoIntegration`** — PDF text extraction utility
- Calls PDF.co API to upload and convert PDF attachments to plaintext
- Used by `SubmissionExtractionAction` to get document text before passing to AI
- API key configured in the class (see Security Notes)

**`SubmissionExtractionAction`**
- `@InvocableMethod extractData(List<Input>)` and `@AuraEnabled extractSubmissionData(String submissionId)`
- Flow:
  1. Queries `ContentDocumentLink` records on the Submission
  2. For each PDF attachment: calls PDF.co upload → PDF.co text extraction
  3. Falls back to `Body__c` (email body) if no documents or PDF.co fails
  4. Passes extracted text to Agentforce `Submission_Data_Extraction` prompt template
  5. Parses JSON response; maps fields to `Submission__c`
  6. Updates `Extraction_Status__c`, `Extraction_Confidence__c`, `Extraction_Log__c`

**`Extract_Submission_Data`** AutoLaunchedFlow — wraps the invocable action

**`submissionExtractButton` LWC** — Quick Action on the Submission record page
- "Extract with Agentforce" button with spinner
- Shows extracted data summary on success

**`Submission_Data_Extraction`** GenAiPromptTemplate — must be created manually in Prompt Builder

**Quick Action** `Submission__c.Extract_with_Agentforce`

---

### US-010 — Missing Information Detection & Broker Follow-Up Draft (SCRUM-12)

**Branch:** SCRUM-12-us-010 — **not yet merged to main**  
**What was built:**

**4 new `Submission__c` fields:** Completeness_Status__c, Follow_Up_Email_Draft__c, Line_of_Business__c, Number_of_Employees__c

**`Missing_Item__c`** custom object (Master-Detail to Submission__c)

**`Submission_Requirement__mdt`** custom metadata type (6 seeded Workers Comp rules)

**`SubmissionValidationAction`**
- `@InvocableMethod` and `@AuraEnabled`
- Flow:
  1. Loads active `Submission_Requirement__mdt` rules filtered by `Line_of_Business__c`
  2. Evaluates each rule (required field check, document keyword search, conditional field)
  3. Deletes existing `Missing_Item__c` records for the submission
  4. Inserts new `Missing_Item__c` records for each failed rule
  5. Sets `Completeness_Status__c`: Complete / Needs Review / Incomplete
  6. Calls Agentforce `Submission_Follow_Up_Email` prompt template to draft follow-up email
  7. Falls back to rule-based template if Agentforce unavailable
  8. Saves draft to `Follow_Up_Email_Draft__c`

**`submissionFollowUpEmail` LWC** — embedded on Submission record page
- "Validate Submission" button
- Displays missing items list with severity badges
- Shows AI-drafted email (editable text area)
- "Send Email" and "Save Draft" actions

**`Submission_Follow_Up_Email`** GenAiPromptTemplate — must be created manually in Prompt Builder

---

### US-011 — Risk Indicators & Appetite Alignment (SCRUM-13)

**Branch:** SCRUM-13-us-011 — **not yet merged to main**  
**What was built:**

**4 new `Submission__c` fields:** Risk_Score__c, Appetite_Score__c, Review_Priority__c, Risk_Summary__c

**`Submission_Risk_Signal__c`** custom object (Master-Detail to Submission__c)

**`Risk_Appetite_Rule__mdt`** custom metadata type (5 seeded Workers Comp rules)

**`MockRiskApiService`** — deterministic external risk API mock
- Scores based on payroll thresholds, NAICS presence, location count, completeness percentage
- Returns `riskScore` (0–100) and `appetiteScore` (0–100)

**`RiskSignalService`**
- `@AuraEnabled evaluateRisk(String submissionId)`
- Flow:
  1. Loads active `Risk_Appetite_Rule__mdt` rules for the submission's LOB
  2. Evaluates: FieldThreshold, FieldBlank, FieldNotBlank, DocumentMissing, DocumentPresent
  3. Deletes existing `Submission_Risk_Signal__c` records
  4. Inserts new signal records for each triggered rule
  5. Calls `MockRiskApiService` for external risk and appetite scores
  6. Calls Agentforce `Submission_Risk_Summary` prompt template for underwriter brief
  7. Updates `Risk_Score__c`, `Appetite_Score__c`, `Review_Priority__c`, `Risk_Summary__c`

**`submissionRiskSignals` LWC** — embedded on Submission record page
- "Evaluate Risk" button
- Color-coded signal cards (Critical=red, High=orange, Medium=yellow, Low=blue, Info=grey)
- Scores panel: Risk Score, Appetite Score, Review Priority
- AI-generated underwriter brief

**`Submission_Risk_Summary`** GenAiPromptTemplate — must be created manually in Prompt Builder

---

## 5. Apex Class Inventory

| Class | Purpose | Sharing | Entry Points |
|---|---|---|---|
| `SubmissionEmailHandler` | Inbound email entry point | global | `Messaging.InboundEmailHandler` |
| `EmailParserHandler` | Alternative monolithic email handler | global | `Messaging.InboundEmailHandler` |
| `SubmissionEmailService` | Creates Submission_Email__c from email | without sharing | Static method |
| `SubmissionFileService` | Stores email attachments as Files | without sharing | Static method |
| `ProcessSubmissionEmailAction` | Promotes email to Submission | with sharing | `@InvocableMethod`, `@AuraEnabled` |
| `SubmissionsInboxController` | Data provider for inbox LWC | with sharing | `@AuraEnabled(cacheable=true)` |
| `SubmissionExtractionAction` | AI data extraction from documents | with sharing | `@InvocableMethod`, `@AuraEnabled` |
| `SubmissionValidationAction` | Completeness check + follow-up draft | with sharing | `@InvocableMethod`, `@AuraEnabled` |
| `RiskSignalService` | Risk scoring and appetite matching | with sharing | `@AuraEnabled` |
| `MockRiskApiService` | Deterministic external API mock | with sharing | Static method |
| `PDFcoIntegration` | PDF text extraction via pdf.co API | with sharing | Static method |

**Test classes:** `SubmissionEmailHandlerTest`, `SubmissionEmailServiceTest`, `SubmissionFileServiceTest`, `ProcessSubmissionEmailActionTest`, `SubmissionsInboxControllerTest`, `SubmissionExtractionActionTest`, `SubmissionValidationActionTest`, `RiskSignalServiceTest`, `CreateSubmissionFromEmailTest`

---

## 6. LWC Component Inventory

| Component | Location | Purpose |
|---|---|---|
| `submissionsInbox` | App page (FlexiPage) | Email inbox with process actions |
| `submissionExtractButton` | Submission quick action | Triggers AI data extraction |
| `submissionFollowUpEmail` | Submission record page | Validation + AI follow-up email draft |
| `submissionRiskSignals` | Submission record page | Risk evaluation and signal display |

---

## 7. Flow Inventory

| Flow | Type | Purpose | Status |
|---|---|---|---|
| `Process_Submission_Email` | AutoLaunched | Wraps `ProcessSubmissionEmailAction` for Agentforce | Active |
| `Extract_Submission_Data` | AutoLaunched | Wraps `SubmissionExtractionAction` for Agentforce | Active |

---

## 8. Prompt Templates (Agentforce)

These must be created manually in Prompt Builder within the org — the metadata files define the template but the org must register them.

| Template | Used By | Purpose |
|---|---|---|
| `Submission_Data_Extraction` | `SubmissionExtractionAction` | Extract structured submission fields from document text |
| `Submission_Follow_Up_Email` | `SubmissionValidationAction` | Draft a broker follow-up email listing missing items |
| `Submission_Risk_Summary` | `RiskSignalService` | Generate a concise underwriter brief from risk signals |

---

## 9. Security Model

### Permission Set — Agentforce_POC_Access

Grants FLS (read + edit) on all custom fields for `Submission_Email__c`, `Submission__c`, `Missing_Item__c`, and `Submission_Risk_Signal__c`. Assign to all users who work with the inbox or submission records.

### Sharing & Context

| Class | Sharing Model | Rationale |
|---|---|---|
| `SubmissionEmailService` | `without sharing` | Inbound email must succeed regardless of user permissions |
| `SubmissionFileService` | `without sharing` | Same rationale as above |
| All other classes | `with sharing` | Respect org-wide defaults and user access |

### Known Security Issue

`PDFcoIntegration.cls` contains a hardcoded API key for the pdf.co service. This credential is committed to source control and visible to anyone with repo access.

**Required remediation before any non-demo deployment:**
1. Rotate the pdf.co API key immediately
2. Store it in a Salesforce Named Credential or Custom Metadata record
3. Update `PDFcoIntegration` to reference the Named Credential

---

## 10. Deployment Inventory

### Merged to Main

| Story | What Deployed |
|---|---|
| SCRUM-4 / US-004 | Submission__c object, layout, tab |
| SCRUM-10 | Agentforce_POC app, tabs |
| SCRUM-5 / US-005 | Submission_Email__c object + layout, SubmissionEmailHandler, SubmissionEmailService, SubmissionFileService, EmailParserHandler, Agentforce_POC_Access permission set |
| SCRUM-7 / US-007 | ProcessSubmissionEmailAction, Process_Submission_Email flow |
| SCRUM-6 / US-006 | submissionsInbox LWC, SubmissionsInboxController, Submissions_Inbox_Page FlexiPage, list view, Body__c field on Submission__c |

### Feature Branches (Pending Merge)

| Branch | Story | Status |
|---|---|---|
| SCRUM-11-us-009 | US-009 AI data extraction | Built; deployment package at `manifest/package-us009.xml` |
| SCRUM-12-us-010 | US-010 Missing info + follow-up draft | Built; deployment package at `manifest/package-us010.xml` |
| SCRUM-13-us-011 | US-011 Risk signals + appetite match | Built; deployment package at `manifest/package-us011.xml` |

---

## 11. Future Roadmap (Evident from Architecture)

| Area | Design Signal | Placeholder Objects/Fields |
|---|---|---|
| Agentforce autonomous processing | AutoLaunched flows callable by agents; `@InvocableMethod` on all action classes | All flows |
| Loss history integration | `Loss_Year__c` object defined but not wired | Loss_Year__c |
| Principal/officer management | `Officer__c` object defined but not wired | Officer__c |
| PDF watermarking / approval stamping | `PDFcoIntegration` class with pdf.co write capability | PDFcoIntegration.cls |
| Underwriting workflow | `Submission__c` fields for triage decisions, WC_Class_Location__c for detailed coverage | WC_Class_Location__c, Appetite_Flag__c |
| Bulk import | Architecture supports it; no batch processing implemented | — |
| External risk scoring | `MockRiskApiService` is a placeholder for a live API | MockRiskApiService.cls |
