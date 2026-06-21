/**
 * ExtractSubmissionDataRAGAction
 *
 * NEW agent route for submission data extraction, grounded by RAG over the
 * Data Cloud Data Library. This runs in PARALLEL to SubmissionExtractionAction
 * (the PDF.co route), which is intentionally left untouched and still works.
 *
 * POC scoping note: the Data Library holds ONLY the current submission's documents at a
 * time (a manual workaround — the operator clears the library and loads just the docs from
 * the incoming email). So the retriever needs no per-submission filter; the whole library
 * IS that submission. No Submission_Document__c correlation is required.
 *
 * Flow:
 *   1. Call the retriever-grounded prompt template 'Submission_Data_Extraction_RAG'. Its
 *      retriever searches the (single-submission) Data Library and grounds the prompt.
 *   2. Reuse the same JSON -> Submission__c field mapping as the PDF.co route to write the
 *      results back to the submission identified by submissionId.
 *
 * The retriever attachment is configured in Prompt Builder. The small stringVal/dateVal
 * helpers are duplicated here (rather than refactored out of SubmissionExtractionAction) so
 * the existing working class is not modified.
 */
public with sharing class ExtractSubmissionDataRAGAction {

    private static final String PROMPT_TEMPLATE = 'Submission_Data_Extraction_RAG';

    public class ExtractionRequest {
        @InvocableVariable(required=true label='Submission ID')
        public String submissionId;
    }

    public class ExtractionResult {
        @InvocableVariable(label='Success')
        public Boolean success;
        @InvocableVariable(label='Message')
        public String message;
    }

    @InvocableMethod(
        label='Extract Submission Data (Data Library)'
        description='Extracts structured insurance data from a submission, grounded by RAG over the Data Cloud Data Library.'
    )
    public static List<ExtractionResult> extractDataInvocable(List<ExtractionRequest> requests) {
        List<ExtractionResult> results = new List<ExtractionResult>();
        for (ExtractionRequest req : requests) {
            ExtractionResult res = new ExtractionResult();
            try {
                extractData(req.submissionId);
                res.success = true;
                res.message = 'Extraction complete';
            } catch (Exception e) {
                res.success = false;
                res.message = e.getMessage();
            }
            results.add(res);
        }
        return results;
    }

    @AuraEnabled
    public static void extractData(String submissionId) {
        Submission__c sub = [
            SELECT Id, Name
            FROM   Submission__c
            WHERE  Id = :submissionId
            LIMIT  1
        ];

        try {
            ConnectApi.EinsteinPromptTemplateGenerationsInput input =
                new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            input.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
            input.additionalConfig.applicationName = 'PromptTemplateGenerationsInvocable';
            input.isPreview = false;

            // No inputs needed: the template's retriever searches the (single-submission)
            // Data Library and grounds the prompt itself. submissionId only identifies the
            // record to update, below.
            input.inputParams = new Map<String, ConnectApi.WrappedValue>();

            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation response =
                ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(PROMPT_TEMPLATE, input);

            String rawJson = response.generations[0].text;
            Map<String, Object> extracted = (Map<String, Object>) JSON.deserializeUntyped(rawJson);

            sub.Insured_Name__c           = stringVal(extracted, 'insuredName');
            sub.Policy_Effective_Date__c  = dateVal(extracted, 'policyEffectiveDate');
            sub.Policy_Expiration_Date__c = dateVal(extracted, 'policyExpirationDate');
            sub.Requested_Coverage__c     = stringVal(extracted, 'requestedCoverage');
            sub.Broker_Name__c            = stringVal(extracted, 'brokerName');
            sub.NAICS_Codes__c            = stringVal(extracted, 'naicsCodes');
            sub.Locations__c              = stringVal(extracted, 'locations');

            Object payrollVal = extracted.get('payroll');
            if (payrollVal != null) {
                try { sub.Payroll__c = Decimal.valueOf(String.valueOf(payrollVal)); } catch (Exception ex) {}
            }

            Object confidenceObj = extracted.get('confidence');
            if (confidenceObj != null) {
                sub.Extraction_Confidence__c = JSON.serialize(confidenceObj);
            }

            sub.Extraction_JSON__c   = rawJson;
            sub.Extraction_Status__c = 'Extraction Complete';
            update sub;

        } catch (Exception e) {
            sub.Extraction_Status__c = 'Extraction Failed';
            sub.Extraction_Log__c    = e.getTypeName() + ': ' + e.getMessage() + '\n' + e.getStackTraceString();
            update sub;
            throw e;
        }
    }

    private static String stringVal(Map<String, Object> m, String key) {
        Object v = m.get(key);
        return v != null ? String.valueOf(v) : null;
    }

    private static Date dateVal(Map<String, Object> m, String key) {
        Object v = m.get(key);
        if (v == null) return null;
        try {
            return Date.valueOf(String.valueOf(v));
        } catch (Exception e) {
            return null;
        }
    }
}
