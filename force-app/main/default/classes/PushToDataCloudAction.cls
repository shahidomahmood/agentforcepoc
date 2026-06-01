public with sharing class PushToDataCloudAction {

    @InvocableMethod(
        label='Push Submission Documents to Data Cloud'
        description='Enqueues an async job to push already-created Submission_Document__c records to the Data Cloud Ingestion API. Call after DML that created the document records so the callout runs in a separate transaction.'
        category='Submission Management'
    )
    public static void push(List<String> documentIds) {
        if (documentIds == null || documentIds.isEmpty()) {
            return;
        }
        List<Id> docIds = new List<Id>();
        for (String rawId : documentIds) {
            docIds.add((Id) rawId);
        }
        System.enqueueJob(new DataCloudIngestionQueueable(docIds));
    }
}
