public with sharing class SubmissionDocumentService {

    public static List<Submission_Document__c> createDocumentRecords(Id submissionId) {
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId,
                   ContentDocument.Title,
                   ContentDocument.FileExtension,
                   ContentDocument.ContentSize
            FROM   ContentDocumentLink
            WHERE  LinkedEntityId = :submissionId
        ];

        if (links.isEmpty()) {
            return new List<Submission_Document__c>();
        }

        List<Submission_Document__c> docs = new List<Submission_Document__c>();
        for (ContentDocumentLink link : links) {
            docs.add(new Submission_Document__c(
                Name                   = link.ContentDocument.Title,
                Submission__c          = submissionId,
                Content_Document_Id__c = link.ContentDocumentId,
                Document_Name__c       = link.ContentDocument.Title,
                Document_Type__c       = inferDocumentType(link.ContentDocument.Title),
                File_Extension__c      = link.ContentDocument.FileExtension?.toLowerCase(),
                File_Size_Kb__c        = link.ContentDocument.ContentSize != null
                                             ? (Decimal) link.ContentDocument.ContentSize / 1024
                                             : null,
                Indexing_Status__c     = 'Pending'
            ));
        }

        upsert docs Content_Document_Id__c;
        return docs;
    }

    @TestVisible
    private static String inferDocumentType(String fileName) {
        if (String.isBlank(fileName)) {
            return 'Other';
        }
        String lower = fileName.toLowerCase();
        if (lower.contains('acord125') || lower.contains('acord 125') || lower.contains('acord_125')) {
            return 'ACORD 125';
        }
        if (lower.contains('acord130') || lower.contains('acord 130') || lower.contains('acord_130')) {
            return 'ACORD 130';
        }
        if (lower.contains('loss') && (lower.contains('run') || lower.contains('history'))) {
            return 'Loss Runs';
        }
        if (lower.contains('application')) {
            return 'Application';
        }
        if (lower.contains('supplement')) {
            return 'Supplemental';
        }
        return 'Other';
    }
}
