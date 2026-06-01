/**
 * Pushes Submission_Document__c metadata to the Data Cloud
 * Data Library (ADL_AgentforcePOC_D) via the Streaming Ingestion API.
 *
 * SETUP REQUIRED before deploying to production — see namedCredentials/DataCloud_Ingestion_API:
 *   1. Data Cloud: Ingestion API Connector "SubmissionDocuments" → ADL_AgentforcePOC_D__dlm
 *   2. Salesforce Setup: Named Credential "DataCloud_Ingestion_API" with OAuth
 *      pointing to https://<your-dc-tenant>.c360a.salesforce.com
 *   3. Verify DLM field names match the constants below.
 */
public with sharing class DataCloudIngestionService {

    @TestVisible static String namedCredential = 'DataCloud_Ingestion_API';
    @TestVisible static String connectorName   = 'Submission_Documents';
    @TestVisible static String entityName      = 'Submission_Document';

    public class DocumentPayload {
        public Submission_Document__c doc;
        public Long                   fileSize;
        public String                 mimeType;
    }

    public class IngestionResult {
        public String  contentDocumentId;
        public Boolean success;
        public String  requestId;
        public String  errorMessage;
    }

    public static List<IngestionResult> pushDocuments(
        List<DocumentPayload> payloads,
        String submissionName
    ) {
        String endpoint = 'callout:' + namedCredential
            + '/api/v1/ingest/sources/' + connectorName
            + '/' + entityName;

        String bodyJson = JSON.serialize(new Map<String, Object>{
            'data' => buildRows(payloads, submissionName)
        });

        System.debug(LoggingLevel.ERROR, '=== DataCloudIngestionService.pushDocuments ===');
        System.debug(LoggingLevel.ERROR, 'DC_DEBUG endpoint       : ' + endpoint);
        System.debug(LoggingLevel.ERROR, 'DC_DEBUG connectorName  : ' + connectorName);
        System.debug(LoggingLevel.ERROR, 'DC_DEBUG entityName     : ' + entityName);
        System.debug(LoggingLevel.ERROR, 'DC_DEBUG payloadBytes   : ' + bodyJson.length());
        System.debug(LoggingLevel.ERROR, 'DC_DEBUG payload        : ' + bodyJson);

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(bodyJson);
        req.setTimeout(30000);

        System.debug('DATA CLOUD ENDPOINT: ' + req.getEndpoint());
        System.debug('DATA CLOUD PAYLOAD: ' + req.getBody());

        HttpResponse res;
        try {
            res = new Http().send(req);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'DC_DEBUG callout exception: ' + e.getMessage());
            return errorResults(payloads, 'Callout failed: ' + e.getMessage());
        }

        System.debug(LoggingLevel.ERROR, 'DC_DEBUG responseStatus : ' + res.getStatusCode() + ' ' + res.getStatus());
        System.debug(LoggingLevel.ERROR, 'DC_DEBUG responseBody   : ' + res.getBody());
        System.debug(LoggingLevel.ERROR, 'DC_DEBUG header[Content-Type]  : ' + res.getHeader('Content-Type'));
        System.debug(LoggingLevel.ERROR, 'DC_DEBUG header[X-Request-ID]  : ' + res.getHeader('X-Request-ID'));
        System.debug(LoggingLevel.ERROR, 'DC_DEBUG header[X-Error-Code]  : ' + res.getHeader('X-Error-Code'));
        System.debug(LoggingLevel.ERROR, 'DC_DEBUG header[X-Correlation-Id]: ' + res.getHeader('X-Correlation-Id'));

        Boolean ok = res.getStatusCode() == 200 || res.getStatusCode() == 202;
        String requestId = extractRequestId(res);

        List<IngestionResult> results = new List<IngestionResult>();
        for (DocumentPayload p : payloads) {
            IngestionResult r       = new IngestionResult();
            r.contentDocumentId     = p.doc.Content_Document_Id__c;
            r.success               = ok;
            r.requestId             = requestId;
            r.errorMessage          = ok ? null : 'HTTP ' + res.getStatusCode() + ': ' + res.getBody();
            results.add(r);
        }
        return results;
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static List<Map<String, Object>> buildRows(
        List<DocumentPayload> payloads,
        String submissionName
    ) {
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        for (DocumentPayload p : payloads) {
            rows.add(new Map<String, Object>{
                'DocumentId'     => p.doc.Content_Document_Id__c,
                'SubmissionId'   => (String) p.doc.Submission__c,
                'SubmissionName' => submissionName,
                'DocumentName'   => p.doc.Document_Name__c,
                'DocumentType'   => p.doc.Document_Type__c,
                'ContentType'    => p.mimeType,
                'FileExtension'  => p.doc.File_Extension__c,
                'FileSize'       => p.fileSize,
                'SourceSystem'   => 'Salesforce',
                'LastModified'   => Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''),
                'Metadata'       => JSON.serialize(new Map<String, Object>{
                    'content_document_id' => p.doc.Content_Document_Id__c
                })
            });
        }
        return rows;
    }

    public static String getMimeType(String fileExtension) {
        if (fileExtension == null) {
            return 'application/octet-stream';
        }
        switch on fileExtension.toLowerCase() {
            when 'pdf'  { return 'application/pdf'; }
            when 'docx' { return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'; }
            when 'doc'  { return 'application/msword'; }
            when 'xlsx' { return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'; }
            when 'xls'  { return 'application/vnd.ms-excel'; }
            when 'csv'  { return 'text/csv'; }
            when 'txt'  { return 'text/plain'; }
            when else   { return 'application/octet-stream'; }
        }
    }

    private static String extractRequestId(HttpResponse res) {
        try {
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            return (String) body.get('requestId');
        } catch (Exception ignored) {
            return null;
        }
    }

    private static List<IngestionResult> errorResults(
        List<DocumentPayload> payloads,
        String message
    ) {
        List<IngestionResult> results = new List<IngestionResult>();
        for (DocumentPayload p : payloads) {
            IngestionResult r   = new IngestionResult();
            r.contentDocumentId = p.doc.Content_Document_Id__c;
            r.success           = false;
            r.errorMessage      = message;
            results.add(r);
        }
        return results;
    }
}
