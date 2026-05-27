public with sharing class SubmissionExtractionAction {

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

    @InvocableMethod(label='Extract Submission Data' description='Calls Agentforce to extract structured insurance data from submission documents')
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
            SELECT Id, Name, Extraction_Status__c
            FROM   Submission__c
            WHERE  Id = :submissionId
            LIMIT  1
        ];

        sub.Extraction_Status__c = 'Extraction Pending';
        sub.Extraction_Log__c    = null;
        update sub;

        try {
            String docText = getDocumentText(submissionId);

            String promptName = 'Submission_Data_Extraction';
            ConnectApi.EinsteinPromptTemplateGenerationsInput input =
                new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            input.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
            input.additionalConfig.applicationName = 'PromptTemplateGenerationsInvocable';
            input.isPreview = false;
            Map<String, ConnectApi.WrappedValue> valueMap = new Map<String, ConnectApi.WrappedValue>();
            ConnectApi.WrappedValue docValue = new ConnectApi.WrappedValue();
            docValue.value = docText;
            valueMap.put('Input:DocumentText', docValue);
            input.inputParams = valueMap;

            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation response =
                ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(promptName, input);

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

    private static String getDocumentText(String submissionId) {
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM   ContentDocumentLink
            WHERE  LinkedEntityId = :submissionId
            ORDER BY SystemModstamp DESC
        ];

        if (links.isEmpty()) {
            throw new AuraHandledException('No documents found on this submission.');
        }

        List<Id> docIds = new List<Id>();
        for (ContentDocumentLink cdl : links) {
            docIds.add(cdl.ContentDocumentId);
        }

        List<ContentVersion> versions = [
            SELECT Title, TextPreview, VersionData, FileExtension
            FROM   ContentVersion
            WHERE  ContentDocumentId IN :docIds
              AND  IsLatest = true
            ORDER BY SystemModstamp DESC
        ];

        if (versions.isEmpty()) {
            throw new AuraHandledException('No document versions found.');
        }

        // Use TextPreview as a best-effort text extraction
        // For PDF/Office docs Salesforce populates TextPreview (up to 1000 chars)
        // Combine all available text
        List<String> textParts = new List<String>();
        for (ContentVersion cv : versions) {
            if (String.isNotBlank(cv.TextPreview)) {
                textParts.add('--- Document: ' + cv.Title + ' ---\n' + cv.TextPreview);
            }
        }

        if (textParts.isEmpty()) {
            throw new AuraHandledException('No readable text found in attached documents.');
        }

        return String.join(textParts, '\n\n');
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
