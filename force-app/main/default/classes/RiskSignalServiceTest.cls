@IsTest
private class RiskSignalServiceTest {

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
    static void testEvaluateRiskSetsScoresAndSignals() {
        Submission__c sub = [SELECT Id FROM Submission__c LIMIT 1];

        Test.startTest();
        RiskSignalService.evaluateRisk(sub.Id);
        Test.stopTest();

        Submission__c updated = [
            SELECT Risk_Score__c, Appetite_Score__c, Review_Priority__c, Risk_Summary__c
            FROM   Submission__c WHERE Id = :sub.Id
        ];
        System.assertNotEquals(null, updated.Risk_Score__c,    'Risk score should be set');
        System.assertNotEquals(null, updated.Appetite_Score__c, 'Appetite score should be set');
        System.assertNotEquals(null, updated.Review_Priority__c, 'Priority should be set');

        List<Submission_Risk_Signal__c> signals = [
            SELECT Signal_Type__c, Severity__c, Source__c
            FROM   Submission_Risk_Signal__c WHERE Submission__c = :sub.Id
        ];
        System.assert(!signals.isEmpty(), 'Should generate risk signals');
    }

    @IsTest
    static void testEvaluateRiskClearsOldSignals() {
        Submission__c sub = [SELECT Id FROM Submission__c LIMIT 1];
        insert new Submission_Risk_Signal__c(
            Submission__c  = sub.Id,
            Signal_Type__c = 'Stale Signal',
            Severity__c    = 'Low',
            Source__c      = 'Local Rule'
        );

        Test.startTest();
        RiskSignalService.evaluateRisk(sub.Id);
        Test.stopTest();

        List<Submission_Risk_Signal__c> stale = [
            SELECT Id FROM Submission_Risk_Signal__c
            WHERE Submission__c = :sub.Id AND Signal_Type__c = 'Stale Signal'
        ];
        System.assertEquals(0, stale.size(), 'Old signals should be deleted before re-evaluation');
    }

    @IsTest
    static void testGetSignals() {
        Submission__c sub = [SELECT Id FROM Submission__c LIMIT 1];
        insert new Submission_Risk_Signal__c(
            Submission__c  = sub.Id,
            Signal_Type__c = 'High Payroll Exposure',
            Severity__c    = 'High',
            Source__c      = 'Local Rule'
        );

        Test.startTest();
        List<Submission_Risk_Signal__c> results = RiskSignalService.getSignals(sub.Id);
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return the inserted signal');
        System.assertEquals('High Payroll Exposure', results[0].Signal_Type__c);
    }

    @IsTest
    static void testHighPayrollTriggersHighPriority() {
        Submission__c sub = [SELECT Id FROM Submission__c LIMIT 1];

        Test.startTest();
        RiskSignalService.evaluateRisk(sub.Id);
        Test.stopTest();

        Submission__c updated = [SELECT Review_Priority__c FROM Submission__c WHERE Id = :sub.Id];
        System.assertEquals('High Priority', updated.Review_Priority__c,
            'Payroll > $2M with missing NAICS docs should be High Priority');
    }
}
