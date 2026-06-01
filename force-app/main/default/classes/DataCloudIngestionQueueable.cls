public class DataCloudIngestionQueueable implements Queueable, Database.AllowsCallouts {

    private final List<Id> documentIds;
    private final Id       submissionId; // may be null when called directly via PushToDataCloudAction

    public DataCloudIngestionQueueable(List<Id> documentIds) {
        this(documentIds, null);
    }

    public DataCloudIngestionQueueable(List<Id> documentIds, Id submissionId) {
        this.documentIds  = documentIds;
        this.submissionId = submissionId;
    }

    public void execute(QueueableContext ctx) {
        List<Submission_Document__c> docs = [
            SELECT Id, Submission__c, Submission__r.Name,
                   Content_Document_Id__c, Document_Name__c, Document_Type__c, File_Extension__c
            FROM   Submission_Document__c
            WHERE  Id IN :documentIds
        ];

        if (docs.isEmpty()) {
            return;
        }

        Id     resolvedSubmissionId = submissionId != null ? submissionId : docs[0].Submission__c;
        String submissionName       = docs[0].Submission__r.Name;

        Set<Id> contentDocIds = new Set<Id>();
        for (Submission_Document__c doc : docs) {
            if (String.isNotBlank(doc.Content_Document_Id__c)) {
                contentDocIds.add((Id) doc.Content_Document_Id__c);
            }
        }

        Map<Id, ContentVersion> versionByDocId = queryLatestVersions(contentDocIds);

        List<DataCloudIngestionService.DocumentPayload> eligible  = new List<DataCloudIngestionService.DocumentPayload>();
        Map<Id, String>                                 skipErrors = new Map<Id, String>();

        for (Submission_Document__c doc : docs) {
            if (String.isBlank(doc.Content_Document_Id__c)) {
                skipErrors.put(doc.Id, 'ContentVersion not found for document.');
                continue;
            }
            ContentVersion cv = versionByDocId.get((Id) doc.Content_Document_Id__c);
            if (cv == null) {
                skipErrors.put(doc.Id, 'ContentVersion not found for document.');
                continue;
            }
            DataCloudIngestionService.DocumentPayload p = new DataCloudIngestionService.DocumentPayload();
            p.doc      = doc;
            p.fileSize = cv.ContentSize;
            p.mimeType = DataCloudIngestionService.getMimeType(cv.FileType);
            eligible.add(p);
        }

        // ── Callout (no DML has run in this transaction above) ─────────────────
        Map<String, DataCloudIngestionService.IngestionResult> resultByContentDocId =
            new Map<String, DataCloudIngestionService.IngestionResult>();

        if (!eligible.isEmpty()) {
            for (DataCloudIngestionService.IngestionResult r :
                    DataCloudIngestionService.pushDocuments(eligible, submissionName)) {
                resultByContentDocId.put(r.contentDocumentId, r);
            }
        }

        // ── DML: update Submission_Document__c status ─────────────────────────
        Integer failCount = 0;
        List<Submission_Document__c> toUpdate = new List<Submission_Document__c>();

        for (Submission_Document__c doc : docs) {
            String skipError = skipErrors.get(doc.Id);
            if (skipError != null) {
                doc.Indexing_Status__c = 'Failed';
                doc.Error_Message__c   = skipError;
                failCount++;
            } else {
                DataCloudIngestionService.IngestionResult r = resultByContentDocId.get(doc.Content_Document_Id__c);
                if (r != null) {
                    doc.Indexing_Status__c        = r.success ? 'Indexed' : 'Failed';
                    doc.Data_Cloud_Document_Id__c = r.requestId;
                    doc.Error_Message__c          = r.errorMessage;
                    if (!r.success) {
                        failCount++;
                    }
                }
            }
            toUpdate.add(doc);
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }

        // ── DML: roll up status to Submission ─────────────────────────────────
        String submissionStatus;
        if (failCount == 0) {
            submissionStatus = 'Indexed';
        } else if (failCount == docs.size()) {
            submissionStatus = 'Failed';
        } else {
            submissionStatus = 'Partial';
        }
        update new Submission__c(Id = resolvedSubmissionId, Indexing_Status__c = submissionStatus);
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    private static Map<Id, ContentVersion> queryLatestVersions(Set<Id> contentDocIds) {
        Map<Id, ContentVersion> result = new Map<Id, ContentVersion>();
        if (contentDocIds.isEmpty()) {
            return result;
        }
        for (ContentVersion cv : [
            SELECT ContentDocumentId, FileType, ContentSize
            FROM   ContentVersion
            WHERE  ContentDocumentId IN :contentDocIds
            ORDER BY VersionNumber DESC
        ]) {
            if (!result.containsKey(cv.ContentDocumentId)) {
                result.put(cv.ContentDocumentId, cv);
            }
        }
        return result;
    }
}
