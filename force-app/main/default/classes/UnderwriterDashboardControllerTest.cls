@IsTest
private class UnderwriterDashboardControllerTest {

    @TestSetup
    static void makeData() {
        Submission_Email__c email = new Submission_Email__c(
            Subject__c       = 'WC Submission',
            From_Email__c    = 'broker@test.com',
            From_Name__c     = 'Test Broker',
            Status__c        = 'Processed',
            Received_Date__c = DateTime.now()
        );
        insert email;

        List<Submission__c> subs = new List<Submission__c>{
            new Submission__c(
                Name                   = '20260101-Alpha-Submission',
                Source__c              = 'Email',
                Submission_Email__c    = email.Id,
                Received_Date__c       = DateTime.now(),
                Broker_Name__c         = 'Alpha Broker',
                Completeness_Status__c = 'Ready for Review',
                Review_Priority__c     = 'High Priority'
            ),
            new Submission__c(
                Name                   = '20260102-Beta-Submission',
                Source__c              = 'Email',
                Submission_Email__c    = email.Id,
                Received_Date__c       = DateTime.now(),
                Broker_Name__c         = 'Beta Broker',
                Completeness_Status__c = 'Additional Information Required'
            )
        };
        insert subs;

        insert new Missing_Item__c(
            Submission__c      = subs[1].Id,
            Missing_Message__c = 'Payroll is required',
            Severity__c        = 'Critical',
            Is_Resolved__c     = false,
            Sort_Order__c      = 1
        );
    }

    @IsTest
    static void testKpisReturnExpectedCounts() {
        Test.startTest();
        UnderwriterDashboardController.DashboardData d = UnderwriterDashboardController.getDashboardData();
        Test.stopTest();

        System.assertEquals(2, d.totalSubmissions,    'Total should be 2');
        System.assertEquals(2, d.newSubmissions,      'Both submissions within last 7 days');
        System.assertEquals(1, d.pendingReview,       'One submission ready for review');
        System.assertEquals(1, d.missingInformation,  'One submission with missing info');
        System.assertEquals(1, d.highRiskSubmissions, 'One high priority submission');
    }

    @IsTest
    static void testChartDataIsPopulated() {
        Test.startTest();
        UnderwriterDashboardController.DashboardData d = UnderwriterDashboardController.getDashboardData();
        Test.stopTest();

        System.assertNotEquals(null, d.intakeByDay,      'intakeByDay must not be null');
        System.assert(!d.intakeByDay.isEmpty(),          'intakeByDay should have entries');
        System.assertNotEquals(null, d.statusBreakdown,  'statusBreakdown must not be null');
        System.assertEquals(5, d.statusBreakdown.size(), 'statusBreakdown should have 5 entries');
        System.assertEquals(3, d.riskDistribution.size(),'riskDistribution should have 3 buckets');
        System.assertEquals(5, d.documentsByType.size(), 'documentsByType should have 5 doc types');
    }

    @IsTest
    static void testMissingInfoQueueReturnsCorrectData() {
        Test.startTest();
        UnderwriterDashboardController.DashboardData d = UnderwriterDashboardController.getDashboardData();
        Test.stopTest();

        System.assertEquals(1, d.missingInfoQueue.size(), 'One submission in missing info queue');
        UnderwriterDashboardController.MissingInfoRow row = d.missingInfoQueue[0];
        System.assertEquals('Beta Broker', row.brokerName,   'Broker name should match');
        System.assertEquals(1,             row.missingCount, 'Should have 1 unresolved missing item');
    }

    @IsTest
    static void testRecentActivityReturnsAllSubmissions() {
        Test.startTest();
        UnderwriterDashboardController.DashboardData d = UnderwriterDashboardController.getDashboardData();
        Test.stopTest();

        System.assertEquals(2, d.recentActivity.size(), 'Both submissions should appear in recent activity');
    }

    @IsTest
    static void testStatusLabelsAreCorrect() {
        Test.startTest();
        UnderwriterDashboardController.DashboardData d = UnderwriterDashboardController.getDashboardData();
        Test.stopTest();

        // Most-recent is sub[0] (both inserted same instant, order may vary; check both statuses exist)
        Set<String> statuses = new Set<String>();
        for (UnderwriterDashboardController.RecentRow r : d.recentActivity) {
            statuses.add(r.status);
        }
        System.assert(statuses.contains('Ready for Review'), 'Ready for Review status expected');
        System.assert(statuses.contains('Missing Information'), 'Missing Information status expected');
    }
}
