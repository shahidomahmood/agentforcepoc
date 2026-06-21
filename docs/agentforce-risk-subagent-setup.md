# Submission Intake Agent — Risk Assessment subagent

Third capability under the single **Submission Intake Agent** (after Extraction and Validate &
Draft Email). Same additive recipe: a thin invocable wrapper exposes the existing
`RiskSignalService` logic to the planner, then you add a subagent + action in Studio and we
re-retrieve the agent metadata. Nothing existing is changed — the LWC wizard's risk button keeps
working untouched.

## What was built in code (this repo)

| Artifact | Path | Role |
|----------|------|------|
| `EvaluateRiskAction` | `force-app/main/default/classes/` | New `@InvocableMethod` agent action **"Evaluate Submission Risk"**. Delegates to `RiskSignalService.evaluateRisk(submissionId)` (which is `@AuraEnabled` only and could not be called by an agent), then re-reads the record and returns `success`, `message`, `riskScore`, `appetiteScore`, `reviewPriority`. The service is **not modified**. |
| `EvaluateRiskActionTest` | `force-app/main/default/classes/` | Happy path (scores returned) + failure path (missing record → failure result). |
| `Agentforce_POC_Access` (permset) | `force-app/main/default/permissionsets/` | Added `<classAccesses>EvaluateRiskAction</classAccesses>`. All object/field perms the action touches (`Submission_Risk_Signal__c` CRUD, `Risk_Score__c`/`Appetite_Score__c`/`Review_Priority__c`/`Risk_Summary__c` FLS, and the read fields) were **already present** — class access is the only new grant. |
| `Submission_Risk_Summary` | `force-app/main/default/genAiPromptTemplates/` | **Reference spec only — NOT deployed** (`.forceignore` excludes `genAiPromptTemplates/`). Fixed the committed `<type>` drift `SalesEmail` → `Flex`. |

The action writes the **same record fields** the wizard reads, so the wizard's Risk Assessment
panel populates identically whether a human clicks the button or the agent runs the action.

## What you do before testing the agent

### A. Verify the prompt template body is NOT blank (the fallback trap)
`RiskSignalService` drafts the underwriter brief via the `Submission_Risk_Summary` template, but it
**catches any failure and falls back to a canned summary**. An empty/blank template body in Prompt
Builder runs an empty prompt → silent fallback (this is exactly what bit the follow-up email). So:

1. **Setup → Prompt Builder → `Submission_Risk_Summary`.**
2. Confirm Type **Flex**, Status **Active/Published**, and the **prompt body is populated** — paste
   from `genAiPromptTemplates/Submission_Risk_Summary.genAiPromptTemplate-meta.xml` if blank.
3. Confirm the Input variables exist with these **exact** API names (they must match the Apex
   `Input:` keys): `InsuredName`, `LineOfBusiness`, `RiskSignals`, `Scores`.
4. Preview to confirm it returns real brief text.

> Not blocking: if the template is blank the action still succeeds and writes the fallback brief —
> you just won't get the AI-written version in the demo.

### B. Deploy code (your CLI — sandbox can't reach the org)
```bash
$env:LC_ALL = "en_US.UTF-8"   # avoids the cosmetic Finalizing locale error
sf project deploy start --source-dir force-app
sf apex run test --tests EvaluateRiskActionTest --result-format human
```
Ensure the agent service user still has the **Agentforce POC Access** permset (it does from the
validate build; the new class access rides along on deploy).

## What you build in Studio (Claude can't click here)

You're on the click-based **Add Action** builder, creating **agent v3** (v2 = extraction +
validate). Mirror the validate subagent exactly.

### Step 1 — New subagent
- **Submission Intake Agent → New Subagent (Topic).**
- Label: **Evaluate Risk**
- Description: *"Assess the risk of an insurance submission against underwriting appetite rules and
  a risk-scoring service, and produce an underwriter risk brief."*
- Reasoning instructions (same imperative anti-stall pattern as validate):
  > Help the user assess a submission's risk. If the user has not given the submission's record Id,
  > ask for it first. Once you have the Id, **immediately call the Evaluate Risk action in the same
  > turn — never reply "one moment" or "processing."** Then report the action's outputs: state the
  > Risk Score, Appetite Score and Review Priority, and relay the Message. Only report values the
  > action returns — never invent scores or signals.

### Step 2 — Add the action
- In the **Evaluate Risk** subagent → **Add Action → Reference Action**.
  - Reference Action Type: **Apex**
  - Category: **Invocable Method**
  - Reference Action: **Evaluate Submission Risk** (`EvaluateRiskAction`)
  - Active: **yes**
- Action label: **Evaluate Risk**
- **Input** — `submissionId` (Submission ID): **Agent Populated**, **Required**. (Collect from the
  user; the agent must have the record Id before running.)
- **Outputs** — show these in the conversation so the agent reports real numbers:
  - `message` (Message) — **Show in conversation**
  - `riskScore` (Risk Score) — **Show in conversation**
  - `appetiteScore` (Appetite Score) — **Show in conversation**
  - `reviewPriority` (Review Priority) — **Show in conversation**
  - `success` (Success) — **Hidden**
- No user-confirmation gate (the action only scores/writes — it sends nothing).

### Step 3 — Router transition
Add a router transition `go_to_Evaluate_Risk` to the **Evaluate Risk** subagent (same as
`go_to_Validate_Draft_Email`), so a message like *"evaluate risk for submission &lt;id&gt;"* routes here.

### Step 4 — Preview test
*"Evaluate risk for submission a00g500000aDYrzAAG"* → router → Evaluate Risk subagent → action runs
→ agent reports Risk Score / Appetite Score / Review Priority. Confirm the Submission record's
Risk fields + Risk Summary populate (and the wizard's Risk panel matches).

## Step 5 — Retrieve the agent metadata (your CLI, I review + commit)
Activation/edit will likely bump the bundle to **v3**:
```bash
sf project retrieve start \
  --metadata "Bot:Submission_Intake_Agent" "GenAiPlannerBundle:Submission_Intake_Agent_v3" \
             "PermissionSet:Agentforce_POC_Access"
```
Then I review the diff and we commit Apex + permset + agent metadata together.

## Notes
- `EvaluateRiskAction` is a separate wrapper class (not an edit to `RiskSignalService`) so the
  working service/wizard code is never touched — same pattern as `ExtractSubmissionDataRAGAction`.
- v3 can be Preview-tested as a draft without activating; activate only when you want risk live in a
  channel (v1 = extraction is still the active version unless you've since activated a later one).
- Remaining optional capabilities under this agent: follow-up email **send** (outward — needs a
  confirmation gate) and document **indexing** (`IndexSubmissionAction`, already invocable).
