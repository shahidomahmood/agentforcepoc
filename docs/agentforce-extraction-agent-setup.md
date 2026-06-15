# Submission Intake Agent — Extraction (RAG over Data Library)

This is the first capability of a **real, expandable Agentforce agent**. It runs in
**parallel** to the existing PDF.co extraction route — nothing existing was changed or
removed. The old route (`SubmissionExtractionAction` + `Submission_Data_Extraction` template
+ PDF.co) keeps working untouched.

## What was built in code (this repo)

| Artifact | Path | Role |
|----------|------|------|
| `ExtractSubmissionDataRAGAction` | `force-app/main/default/classes/` | New `@InvocableMethod` agent action. Calls the RAG prompt template (whose retriever searches the Data Library) and maps the returned JSON to the `Submission__c` fields. `submissionId` only identifies the record to update. **No PDF.co callout, no document correlation.** |
| `ExtractSubmissionDataRAGActionTest` | `force-app/main/default/classes/` | Mirrors `SubmissionExtractionActionTest` — wrapper + failure path (ConnectApi isn't callable in tests). |
| `Submission_Data_Extraction_RAG` | `force-app/main/default/genAiPromptTemplates/` | **Reference spec only — NOT deployed.** `.forceignore` excludes `genAiPromptTemplates/`, so this file is the blueprint for building the template **by hand** in Prompt Builder (same convention as the existing three templates). Same proven extraction prompt + JSON schema as the original. |

## What you build in Studio (Claude cannot click here)

Agents, planners, topics and the retriever-to-template grounding are UI-built, then
retrieved into the repo. Use these **exact API names** so the retrieved metadata is
predictable.

### Step 0 — Prerequisites
- Data Library is provisioned.
- Note the **retriever API name** for that Data Library: `__________________`.
- **POC workaround (no submission scoping needed):** the library holds **only the current
  submission's documents** at a time. Before processing an email, **clear the library and
  load just the documents from that email**. Because the library only ever contains one
  submission's docs, the retriever needs **no per-submission filter** and we do **not** use
  `Submission_Document__c` for correlation.

### Step 1 — Create the prompt template by hand in Prompt Builder
> The template is **not deployable** (`genAiPromptTemplates/` is in `.forceignore`). Build it
> in the UI using the committed file as the spec.
1. **Setup → Prompt Builder → New Prompt Template.**
   - Type: **Flex**
   - Name it so the **API/Developer name is exactly `Submission_Data_Extraction_RAG`**
     (the Apex action calls this literal — a different name means it won't be found).
   - Paste the prompt instructions + JSON schema from
     `genAiPromptTemplates/Submission_Data_Extraction_RAG.genAiPromptTemplate-meta.xml`.
2. Where the spec has the **`{!$Input:DocumentText}`** line, instead insert your Data Library
   **retriever** resource (insert retriever → choose the chunk/text field to ground).
3. Give the retriever a **broad static search query** so it returns the document content for
   extraction, e.g. *"insurance submission details: insured, broker, coverage, payroll,
   locations, policy dates, NAICS"*. (No dynamic filter — the library is already scoped to
   one submission.)
4. Set **topK** high enough to cover the loaded documents.
5. Preview; confirm it returns the loaded document content.
6. **Publish/Activate** the template.

### Step 2 — Create the agent in Agentforce Studio
1. **Setup → Agentforce Studio → Agents → New Agent** (custom/blank).
   - Label: **Submission Intake Agent**  ·  API name: **Submission_Intake_Agent**
2. Add a **Topic**:
   - Label: **Submission Intake & Triage**  ·  API name: **Submission_Intake_Triage**
   - Scope/instructions: "Extract and triage new insurance submissions and their documents."
3. Add an **Action** to that topic → **Reference an Apex action** →
   **Extract Submission Data (Data Library)** (`ExtractSubmissionDataRAGAction`).
   - Map the input `Submission ID` from the conversation context.
4. Topic instruction so the planner knows when to call it, e.g.:
   *"When the user references a submission and asks to extract or read its documents, call
   Extract Submission Data (Data Library) with that submission's record Id."*
5. **Activate** the agent.

### Step 3 — Retrieve the agent metadata back into the repo
Once activated, tell me the final API names and I'll pull the canonical metadata:
```bash
sf project retrieve start \
  -m "Bot:Submission_Intake_Agent" \
  -m "GenAiPlannerBundle" -m "GenAiPlugin" -m "GenAiFunction" \
  -m "GenAiPromptTemplate:Submission_Data_Extraction_RAG"
```
(We finalize the exact member names from `sf project retrieve start --manifest` or the org's
package once they exist.)

## Verification (end-to-end)

1. **Unit tests still green (old route untouched):**
   `npm run test` and
   `sf apex run test --tests ExtractSubmissionDataRAGActionTest --result-format human`
2. **Deploy:** `sf project deploy start --source-dir force-app`
3. **New RAG route:** load one submission's docs into the library, then in the agent preview
   ask it to extract that submission. Confirm the `Submission__c` fields + `Extraction_JSON__c`
   populate from the retrieved content.
4. **Old route unchanged:** run the existing PDF.co extraction on a different submission and
   confirm it still works — proving the change is purely additive.

## Notes / open items
- Prompt templates are **not deployed** in this project (`.forceignore` excludes
  `genAiPromptTemplates/`); they are hand-built in Prompt Builder. The committed XML files are
  reference specs only. The Apex only needs the template's **API name** to match
  (`Submission_Data_Extraction_RAG`).
- Submission scoping is handled operationally (one submission's docs in the library at a time),
  not by a retriever filter. If the POC later needs multiple submissions co-resident in the
  library, we add a dynamic filter and pass a scope value from the action — the action and
  template are structured so that's a small change, not a rebuild.
- Next capabilities to add as further actions under the same agent: validate/missing-items,
  follow-up email, risk summary, indexing.
