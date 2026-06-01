public with sharing class IndexSubmissionAction {

    @InvocableMethod(
        label='Index Submission Documents in Data Cloud'
        description='Enqueues an async job that creates Submission_Document__c bridge records and pushes document metadata to the Data Cloud Data Library (ADL_AgentforcePOC_D) for Agentforce retrieval.'
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
