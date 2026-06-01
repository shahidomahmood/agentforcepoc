public class SubmissionIndexingQueueable implements Queueable {

    private final Id submissionId;

    public SubmissionIndexingQueueable(Id submissionId) {
        this.submissionId = submissionId;
    }

    public static void enqueue(Id submissionId) {
        System.enqueueJob(new SubmissionIndexingQueueable(submissionId));
    }

    public void execute(QueueableContext ctx) {
        // Create the Submission_Document__c bridge records for every file attached
        // to the submission. The Data Cloud CRM connector syncs these records (and
        // the underlying Salesforce Files) into Data Cloud on its own schedule, so
        // there is no callout here — the bridge object exists purely so we can match
        // a submission to its indexed documents later.
        SubmissionDocumentService.createDocumentRecords(submissionId);
    }
}
