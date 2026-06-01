public class SubmissionIndexingQueueable implements Queueable {

    private final Id submissionId;

    public SubmissionIndexingQueueable(Id submissionId) {
        this.submissionId = submissionId;
    }

    public static void enqueue(Id submissionId) {
        System.enqueueJob(new SubmissionIndexingQueueable(submissionId));
    }

    public void execute(QueueableContext ctx) {
        List<Submission_Document__c> docs = SubmissionDocumentService.createDocumentRecords(submissionId);

        if (docs.isEmpty()) {
            update new Submission__c(Id = submissionId, Indexing_Status__c = 'Indexed');
            return;
        }

        List<Id> docIds = new List<Id>();
        for (Submission_Document__c doc : docs) {
            docIds.add(doc.Id);
        }
        System.enqueueJob(new DataCloudIngestionQueueable(docIds, submissionId));
    }
}
