@isTest
private class ProcessSubmissionEmailActionTest {

    @TestSetup
    static void makeData() {
        insert new Submission_Email__c(
            From_Name__c     = 'Test Broker',
            From_Email__c    = 'broker@test.com',
            Subject__c       = 'New Submission - Test',
            Received_Date__c = DateTime.now(),
            Status__c        = 'Received'
        );
    }

    @isTest
    static void processEmail_createsSubmission() {
        Submission_Email__c email = [SELECT Id, Received_Date__c FROM Submission_Email__c LIMIT 1];

        Test.startTest();
        String submissionId = ProcessSubmissionEmailAction.processEmail(email.Id);
        Test.stopTest();

        Assert.isNotNull(submissionId, 'Should return a Submission ID');
        Submission__c sub = [
            SELECT Source__c, Received_Date__c, Submission_Email__c
            FROM   Submission__c
            WHERE  Id = :submissionId
        ];
        Assert.areEqual('Email',  sub.Source__c);
        Assert.areEqual(email.Id, sub.Submission_Email__c);
    }

    @isTest
    static void processEmail_marksEmailProcessed() {
        Submission_Email__c email = [SELECT Id FROM Submission_Email__c LIMIT 1];

        Test.startTest();
        ProcessSubmissionEmailAction.processEmail(email.Id);
        Test.stopTest();

        Submission_Email__c updated = [SELECT Status__c FROM Submission_Email__c WHERE Id = :email.Id];
        Assert.areEqual('Processed', updated.Status__c);
    }

    @isTest
    static void processEmail_linksExistingAttachments() {
        Submission_Email__c email = [SELECT Id FROM Submission_Email__c LIMIT 1];

        ContentVersion cv = new ContentVersion(
            Title                  = 'BrokerDoc.pdf',
            PathOnClient           = 'BrokerDoc.pdf',
            VersionData            = Blob.valueOf('dummy'),
            FirstPublishLocationId = email.Id
        );
        insert cv;

        Test.startTest();
        String submissionId = ProcessSubmissionEmailAction.processEmail(email.Id);
        Test.stopTest();

        List<ContentDocumentLink> links = [
            SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :submissionId
        ];
        Assert.areEqual(1, links.size(), 'Attachment should be linked to new Submission');
    }

    @isTest
    static void processEmail_noAttachments_doesNotFail() {
        Submission_Email__c email = [SELECT Id FROM Submission_Email__c LIMIT 1];

        Test.startTest();
        String submissionId = ProcessSubmissionEmailAction.processEmail(email.Id);
        Test.stopTest();

        Assert.isNotNull(submissionId, 'Should succeed even with no attachments');
    }

    @isTest
    static void invocableProcess_returnsSubmissionId() {
        Submission_Email__c email = [SELECT Id FROM Submission_Email__c LIMIT 1];

        ProcessSubmissionEmailAction.Input inp = new ProcessSubmissionEmailAction.Input();
        inp.submissionEmailId = email.Id;

        Test.startTest();
        List<ProcessSubmissionEmailAction.Output> outputs =
            ProcessSubmissionEmailAction.process(
                new List<ProcessSubmissionEmailAction.Input>{ inp }
            );
        Test.stopTest();

        Assert.areEqual(1, outputs.size());
        Assert.isNotNull(outputs[0].submissionId);
    }
}
