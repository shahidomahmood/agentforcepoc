@IsTest
private class ExtractSubmissionDataRAGActionTest {

    @TestSetup
    static void makeData() {
        Submission_Email__c email = new Submission_Email__c(
            Subject__c       = 'Test Submission',
            From_Email__c    = 'broker@test.com',
            From_Name__c     = 'John Broker',
            Status__c        = 'Processed',
            Received_Date__c = Date.today()
        );
        insert email;

        Submission__c sub = new Submission__c(
            Name                = '20260615-Broker-Submission',
            Source__c           = 'Email',
            Submission_Email__c = email.Id,
            Received_Date__c    = Date.today()
        );
        insert sub;
    }

    @IsTest
    static void testInvocableHandlesCalloutUnavailable() {
        Submission__c sub = [SELECT Id FROM Submission__c LIMIT 1];

        ExtractSubmissionDataRAGAction.ExtractionRequest req =
            new ExtractSubmissionDataRAGAction.ExtractionRequest();
        req.submissionId = sub.Id;

        // ConnectApi.EinsteinLLM is not callable in test context, so the invocable
        // returns a failure result rather than throwing.
        Test.startTest();
        List<ExtractSubmissionDataRAGAction.ExtractionResult> results =
            ExtractSubmissionDataRAGAction.extractDataInvocable(
                new List<ExtractSubmissionDataRAGAction.ExtractionRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].success);
        System.assert(String.isNotBlank(results[0].message));
    }

    @IsTest
    static void testExtractDataSetsFailedStatus() {
        Submission__c sub = [SELECT Id FROM Submission__c LIMIT 1];

        // The ConnectApi retriever/LLM call is not available in test context, so extraction
        // fails on the callout — we assert it is handled (status set), not stuck pending.
        Test.startTest();
        try {
            ExtractSubmissionDataRAGAction.extractData(sub.Id);
        } catch (Exception e) {
            // Expected — ConnectApi.EinsteinLLM is not callable in test context.
        }
        Test.stopTest();

        Submission__c updated = [
            SELECT Extraction_Status__c, Extraction_Log__c
            FROM   Submission__c
            WHERE  Id = :sub.Id
        ];
        System.assertEquals(
            'Extraction Failed',
            updated.Extraction_Status__c,
            'Failed callout should set status to Extraction Failed'
        );
    }
}
