@IsTest
private class EvaluateRiskActionTest {

    @TestSetup
    static void makeData() {
        Submission_Email__c email = new Submission_Email__c(
            Subject__c       = 'Test Submission',
            From_Email__c    = 'broker@test.com',
            From_Name__c     = 'Test Broker',
            Status__c        = 'Processed',
            Received_Date__c = Date.today()
        );
        insert email;

        Submission__c sub = new Submission__c(
            Source__c           = 'Email',
            Submission_Email__c = email.Id,
            Received_Date__c    = Date.today(),
            Line_of_Business__c = 'Workers Comp',
            Payroll__c          = 3000000,
            NAICS_Codes__c      = '238110',
            Locations__c        = 'New York, New Jersey',
            Insured_Name__c     = 'Test Corp'
        );
        insert sub;
    }

    @IsTest
    static void testInvocableReturnsScores() {
        Submission__c sub = [SELECT Id FROM Submission__c LIMIT 1];

        EvaluateRiskAction.RiskRequest req = new EvaluateRiskAction.RiskRequest();
        req.submissionId = sub.Id;

        // ConnectApi.EinsteinLLM isn't callable in tests, but RiskSignalService catches that and
        // falls back to a generated summary, so evaluateRisk completes and scores are written.
        Test.startTest();
        List<EvaluateRiskAction.RiskResult> results =
            EvaluateRiskAction.evaluateRiskInvocable(
                new List<EvaluateRiskAction.RiskRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success, 'Risk evaluation should succeed');
        System.assertNotEquals(null, results[0].riskScore, 'Risk score should be returned');
        System.assertNotEquals(null, results[0].appetiteScore, 'Appetite score should be returned');
        System.assert(String.isNotBlank(results[0].reviewPriority), 'Review priority should be returned');
        System.assert(results[0].message.contains('Risk Score'), 'Message should report the numbers');
    }

    @IsTest
    static void testInvocableHandlesBadId() {
        // Create then delete a submission so the Id is well-formed but no record exists —
        // RiskSignalService's single-row query throws, and the wrapper reports a failure result.
        Submission__c sub = [SELECT Id FROM Submission__c LIMIT 1];
        Id deletedId = sub.Id;
        delete sub;

        EvaluateRiskAction.RiskRequest req = new EvaluateRiskAction.RiskRequest();
        req.submissionId = deletedId;

        Test.startTest();
        List<EvaluateRiskAction.RiskResult> results =
            EvaluateRiskAction.evaluateRiskInvocable(
                new List<EvaluateRiskAction.RiskRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].success, 'Missing record should produce a failure result');
        System.assert(String.isNotBlank(results[0].message), 'Failure message should be populated');
    }
}
