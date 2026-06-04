public with sharing class IndexSubmissionAction {

    @InvocableMethod(
        label='Capture Submission Documents'
        description='Enqueues an async job that creates Submission_Document__c bridge records for the files attached to a submission. The Data Cloud CRM connector syncs those records and files into Data Cloud; this action does not call out to Data Cloud.'
        category='Submission Management'
    )
    public static void index(List<String> submissionIds) {
        if (Test.isRunningTest()) {
            return;
        }
        for (String sid : submissionIds) {
            SubmissionIndexingQueueable.enqueue((Id) sid);
        }
    }
}
