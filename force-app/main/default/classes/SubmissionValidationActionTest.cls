@IsTest
private class SubmissionValidationActionTest {

    @TestSetup
    static void makeData() {
        Submission_Email__c email = new Submission_Email__c(
            Subject__c      = 'WC Submission',
            From_Email__c   = 'broker@test.com',
            From_Name__c    = 'Test Broker',
            Status__c       = 'Processed',
            Received_Date__c = Date.today()
        );
        insert email;

        Submission__c sub = new Submission__c(
            Name                 = '20260528-Broker-Submission',
            Source__c            = 'Email',
            Submission_Email__c  = email.Id,
            Received_Date__c     = Date.today(),
            Line_of_Business__c  = 'Workers Comp'
        );
        insert sub;
    }

    @IsTest
    static void testValidationFindsAllMissingItems() {
        Submission__c sub = [SELECT Id FROM Submission__c LIMIT 1];

        Test.startTest();
        Integer missingCount = SubmissionValidationAction.validateSubmission(sub.Id);
        Test.stopTest();

        // Expect multiple missing items (payroll, employees, dates, documents)
        System.assert(missingCount > 0, 'Should detect missing items on a blank submission');

        List<Missing_Item__c> items = [SELECT Id, Severity__c FROM Missing_Item__c WHERE Submission__c = :sub.Id];
        System.assertEquals(missingCount, items.size(), 'Missing_Item__c count should match return value');

        Submission__c updated = [SELECT Completeness_Status__c FROM Submission__c WHERE Id = :sub.Id];
        System.assertEquals('Additional Information Required', updated.Completeness_Status__c);
    }

    @IsTest
    static void testValidationCompleteSubmission() {
        Submission__c sub = [SELECT Id FROM Submission__c LIMIT 1];

        sub.Payroll__c                = 500000;
        sub.NAICS_Codes__c            = '5191';
        sub.Policy_Effective_Date__c  = Date.today().addMonths(1);
        sub.Number_of_Employees__c    = 25;
        update sub;

        // Attach a mock ACORD document
        ContentVersion acord = new ContentVersion(
            Title          = 'ACORD 130 Signed',
            PathOnClient   = 'acord130.pdf',
            VersionData    = Blob.valueOf('ACORD form data'),
            IsMajorVersion = true
        );
        insert acord;
        acord = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :acord.Id];
        insert new ContentDocumentLink(
            ContentDocumentId = acord.ContentDocumentId,
            LinkedEntityId    = sub.Id,
            ShareType         = 'V'
        );

        // Attach a mock Loss Run document
        ContentVersion lossRun = new ContentVersion(
            Title          = 'Loss Run 2023',
            PathOnClient   = 'loss_run.pdf',
            VersionData    = Blob.valueOf('Loss run data'),
            IsMajorVersion = true
        );
        insert lossRun;
        lossRun = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :lossRun.Id];
        insert new ContentDocumentLink(
            ContentDocumentId = lossRun.ContentDocumentId,
            LinkedEntityId    = sub.Id,
            ShareType         = 'V'
        );

        Test.startTest();
        Integer missingCount = SubmissionValidationAction.validateSubmission(sub.Id);
        Test.stopTest();

        System.assertEquals(0, missingCount, 'Complete submission should have no missing items');

        Submission__c updated = [SELECT Completeness_Status__c FROM Submission__c WHERE Id = :sub.Id];
        System.assertEquals('Ready for Review', updated.Completeness_Status__c);
    }

    @IsTest
    static void testInvocable() {
        Submission__c sub = [SELECT Id FROM Submission__c LIMIT 1];

        SubmissionValidationAction.ValidationRequest req = new SubmissionValidationAction.ValidationRequest();
        req.submissionId = sub.Id;

        Test.startTest();
        List<SubmissionValidationAction.ValidationResult> results =
            SubmissionValidationAction.validateInvocable(
                new List<SubmissionValidationAction.ValidationRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success);
    }

    @IsTest
    static void testSaveDraft() {
        Submission__c sub = [SELECT Id FROM Submission__c LIMIT 1];

        Test.startTest();
        SubmissionValidationAction.saveDraft(sub.Id, 'Test draft content');
        Test.stopTest();

        Submission__c updated = [SELECT Follow_Up_Email_Draft__c FROM Submission__c WHERE Id = :sub.Id];
        System.assertEquals('Test draft content', updated.Follow_Up_Email_Draft__c);
    }

    @IsTest
    static void testSendEmailNoAddress() {
        Submission__c sub = new Submission__c(
            Name            = 'No-Email-Sub',
            Source__c       = 'Email',
            Received_Date__c = Date.today()
        );
        insert sub;

        Test.startTest();
        try {
            SubmissionValidationAction.sendFollowUpEmail(sub.Id, 'Test body');
            System.assert(false, 'Expected AuraHandledException for missing email');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('No broker email'), 'Wrong error message: ' + e.getMessage());
        }
        Test.stopTest();
    }
}
