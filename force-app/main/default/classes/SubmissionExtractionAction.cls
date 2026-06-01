public with sharing class SubmissionExtractionAction {

    private static final String PDFCO_API_KEY = PDFcoIntegration.API_KEY;
    private static final String PDFCO_UPLOAD_URL  = 'https://api.pdf.co/v1/file/upload/base64';
    private static final String PDFCO_EXTRACT_URL = 'https://api.pdf.co/v1/pdf/convert/to/text';

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
        // Query before any DML so callouts are allowed in the same transaction
        Submission__c sub = [
            SELECT Id, Name, Body__c
            FROM   Submission__c
            WHERE  Id = :submissionId
            LIMIT  1
        ];

        try {
            String docText = getDocumentText(submissionId, sub.Body__c);

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

    private static String getDocumentText(String submissionId, String emailBody) {
        List<String> textParts = new List<String>();

        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM   ContentDocumentLink
            WHERE  LinkedEntityId = :submissionId
            ORDER BY SystemModstamp DESC
        ];

        if (!links.isEmpty()) {
            List<Id> docIds = new List<Id>();
            for (ContentDocumentLink cdl : links) {
                docIds.add(cdl.ContentDocumentId);
            }

            List<ContentVersion> versions = [
                SELECT Title, VersionData, FileExtension, FileType
                FROM   ContentVersion
                WHERE  ContentDocumentId IN :docIds
                  AND  IsLatest = true
                  AND  FileType IN ('PDF', 'Word_x', 'Word', 'Text', 'UNKNOWN')
                ORDER BY SystemModstamp DESC
                LIMIT  3
            ];

            for (ContentVersion cv : versions) {
                try {
                    String extracted = extractTextViaPDFco(cv);
                    if (String.isNotBlank(extracted)) {
                        textParts.add('--- Document: ' + cv.Title + ' ---\n' + extracted);
                    }
                } catch (Exception e) {
                    // Log but continue — try remaining documents
                    System.debug('PDF.co extraction failed for ' + cv.Title + ': ' + e.getMessage());
                }
            }
        }

        // Fall back to email body for image-based PDFs or when no documents are attached
        if (textParts.isEmpty() && String.isNotBlank(emailBody)) {
            textParts.add('--- Email Body ---\n' + emailBody);
        }

        if (textParts.isEmpty()) {
            throw new AuraHandledException(
                'No readable text found. Attach a text-based PDF or ensure the submission email body is populated.'
            );
        }

        return String.join(textParts, '\n\n');
    }

    private static String extractTextViaPDFco(ContentVersion cv) {
        // Step 1: upload the file bytes to PDF.co temporary storage
        String base64Data = EncodingUtil.base64Encode(cv.VersionData);
        String fileName   = (cv.Title + '.' + cv.FileExtension).replaceAll('[^a-zA-Z0-9._-]', '_');

        HttpRequest uploadReq = new HttpRequest();
        uploadReq.setEndpoint(PDFCO_UPLOAD_URL);
        uploadReq.setMethod('POST');
        uploadReq.setHeader('Content-Type', 'application/json');
        uploadReq.setHeader('x-api-key', PDFCO_API_KEY);
        uploadReq.setBody(JSON.serialize(new Map<String, Object>{
            'file' => base64Data,
            'name' => fileName
        }));
        uploadReq.setTimeout(120000);

        HttpResponse uploadRes = new Http().send(uploadReq);
        if (uploadRes.getStatusCode() != 200) {
            throw new AuraHandledException('PDF.co upload failed (' + uploadRes.getStatusCode() + '): ' + uploadRes.getBody());
        }

        Map<String, Object> uploadResult = (Map<String, Object>) JSON.deserializeUntyped(uploadRes.getBody());
        if (uploadResult.get('error') == true) {
            throw new AuraHandledException('PDF.co upload error: ' + uploadResult.get('message'));
        }
        String tempUrl = (String) uploadResult.get('url');

        // Step 2: extract text from the uploaded file
        HttpRequest extractReq = new HttpRequest();
        extractReq.setEndpoint(PDFCO_EXTRACT_URL);
        extractReq.setMethod('POST');
        extractReq.setHeader('Content-Type', 'application/json');
        extractReq.setHeader('x-api-key', PDFCO_API_KEY);
        extractReq.setBody(JSON.serialize(new Map<String, Object>{
            'url'    => tempUrl,
            'inline' => true,
            'async'  => false
        }));
        extractReq.setTimeout(120000);

        HttpResponse extractRes = new Http().send(extractReq);
        if (extractRes.getStatusCode() != 200) {
            throw new AuraHandledException('PDF.co extract failed (' + extractRes.getStatusCode() + '): ' + extractRes.getBody());
        }

        Map<String, Object> extractResult = (Map<String, Object>) JSON.deserializeUntyped(extractRes.getBody());
        if (extractResult.get('error') == true) {
            throw new AuraHandledException('PDF.co extract error: ' + extractResult.get('message'));
        }

        return (String) extractResult.get('body');
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
