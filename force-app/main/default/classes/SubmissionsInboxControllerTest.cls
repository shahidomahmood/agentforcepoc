@isTest
private class SubmissionsInboxControllerTest {

    @isTest
    static void testGetSubmissionEmailsReturnsList() {
        insert new Submission_Email__c(
            From_Name__c      = 'Jane Broker',
            From_Email__c     = 'jane@agency.com',
            Subject__c        = 'WC Submission - Acme Corp',
            Received_Date__c  = DateTime.now(),
            Status__c         = 'Received',
            Attachment_Count__c = 2
        );

        Test.startTest();
        List<Submission_Email__c> results = SubmissionsInboxController.getSubmissionEmails();
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.areEqual('Jane Broker',     results[0].From_Name__c);
        Assert.areEqual('jane@agency.com', results[0].From_Email__c);
        Assert.areEqual('Received',        results[0].Status__c);
    }

    @isTest
    static void testGetSubmissionEmailsOrderedNewestFirst() {
        insert new List<Submission_Email__c>{
            new Submission_Email__c(
                From_Email__c    = 'older@broker.com',
                Subject__c       = 'Older Submission',
                Received_Date__c = DateTime.now().addHours(-3),
                Status__c        = 'Processed'
            ),
            new Submission_Email__c(
                From_Email__c    = 'newer@broker.com',
                Subject__c       = 'Newer Submission',
                Received_Date__c = DateTime.now(),
                Status__c        = 'Received'
            )
        };

        Test.startTest();
        List<Submission_Email__c> results = SubmissionsInboxController.getSubmissionEmails();
        Test.stopTest();

        Assert.areEqual(2, results.size());
        Assert.isTrue(
            results[0].Received_Date__c >= results[1].Received_Date__c,
            'Results should be ordered newest first'
        );
    }

    @isTest
    static void testGetSubmissionEmailsEmpty() {
        Test.startTest();
        List<Submission_Email__c> results = SubmissionsInboxController.getSubmissionEmails();
        Test.stopTest();

        Assert.isNotNull(results);
        Assert.areEqual(0, results.size());
    }
}