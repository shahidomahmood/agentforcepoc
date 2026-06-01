@IsTest
private class SubmissionExtractionActionTest {

    @TestSetup
    static void makeData() {
        Submission_Email__c email = new Submission_Email__c(
            Subject__c     = 'Test Submission',
            From_Email__c  = 'broker@test.com',
            From_Name__c   = 'John Broker',
            Status__c      = 'Processed',
            Received_Date__c = Date.today()
        );
        insert email;

        Submission__c sub = new Submission__c(
            Name                = '20260527-Broker-Submission',
            Source__c           = 'Email',
            Submission_Email__c = email.Id,
            Received_Date__c    = Date.today()
        );
        insert sub;
    }

    @IsTest
    static void testExtractDataNoDocuments() {
        Submission__c sub = [SELECT Id FROM Submission__c LIMIT 1];

        Test.startTest();
        try {
            SubmissionExtractionAction.extractData(sub.Id);
            System.assert(false, 'Expected exception for missing documents');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('No documents'), 'Expected no-documents error');
        }
        Test.stopTest();

        Submission__c updated = [SELECT Extraction_Status__c FROM Submission__c WHERE Id = :sub.Id];
        System.assertEquals('Extraction Failed', updated.Extraction_Status__c);
    }

    @IsTest
    static void testInvocableNoDocuments() {
        Submission__c sub = [SELECT Id FROM Submission__c LIMIT 1];

        SubmissionExtractionAction.ExtractionRequest req = new SubmissionExtractionAction.ExtractionRequest();
        req.submissionId = sub.Id;

        Test.startTest();
        List<SubmissionExtractionAction.ExtractionResult> results =
            SubmissionExtractionAction.extractDataInvocable(
                new List<SubmissionExtractionAction.ExtractionRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].success);
        System.assert(String.isNotBlank(results[0].message));
    }

    @IsTest
    static void testExtractDataWithDocument() {
        Submission__c sub = [SELECT Id FROM Submission__c LIMIT 1];

        ContentVersion cv = new ContentVersion(
            Title           = 'Test Policy Document',
            PathOnClient    = 'test.txt',
            VersionData     = Blob.valueOf('Insured: Acme Corp, Broker: Jane Smith, Effective: 2026-01-01'),
            IsMajorVersion  = true
        );
        insert cv;
        cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId    = sub.Id,
            ShareType         = 'V'
        );
        insert cdl;

        // Verify setup
        List<ContentDocumentLink> links = [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :sub.Id];
        System.assertEquals(1, links.size(), 'CDL should be linked');

        // We cannot call ConnectApi.EinsteinLLM in test context — the extraction will fail
        // but it should set status to Extraction Failed and log the error
        Test.startTest();
        try {
            SubmissionExtractionAction.extractData(sub.Id);
        } catch (Exception e) {
            // Expected — ConnectApi.EinsteinLLM is not callable in test context
        }
        Test.stopTest();

        Submission__c updated = [
            SELECT Extraction_Status__c, Extraction_Log__c
            FROM   Submission__c
            WHERE  Id = :sub.Id
        ];
        System.assertNotEquals('Extraction Pending', updated.Extraction_Status__c, 'Should not be stuck in pending');
    }
}
