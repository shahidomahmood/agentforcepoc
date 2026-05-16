@isTest
private class CreateSubmissionFromEmailTest {

    @isTest
    static void testCreateSubmissionAllFields() {
        CreateSubmissionFromEmail.CreateSubmissionInput input = new CreateSubmissionFromEmail.CreateSubmissionInput();
        input.senderName      = 'Jane Broker';
        input.senderEmail     = 'jane@brokeragency.com';
        input.brokerAgencyName = 'ABC Insurance Agency';
        input.insuredName     = 'Acme Manufacturing LLC';
        input.lineOfBusiness  = 'WC';
        input.effectiveDate   = Date.today().addDays(30);

        Test.startTest();
        List<CreateSubmissionFromEmail.CreateSubmissionOutput> outputs =
            CreateSubmissionFromEmail.createSubmission(
                new List<CreateSubmissionFromEmail.CreateSubmissionInput>{ input }
            );
        Test.stopTest();

        Assert.areEqual(1, outputs.size(), 'Expected one output');
        Assert.isNotNull(outputs[0].submissionId, 'Submission ID should not be null');

        Submission__c created = [
            SELECT Sender_Name__c, Sender_Email__c, Broker_Agency_Name__c,
                   Insured_Name__c, Lines_Requested__c, Effective_Date__c, Status__c
            FROM   Submission__c
            WHERE  Id = :outputs[0].submissionId
        ];

        Assert.areEqual('Jane Broker',              created.Sender_Name__c);
        Assert.areEqual('jane@brokeragency.com',    created.Sender_Email__c);
        Assert.areEqual('ABC Insurance Agency',     created.Broker_Agency_Name__c);
        Assert.areEqual('Acme Manufacturing LLC',   created.Insured_Name__c);
        Assert.areEqual('WC',                       created.Lines_Requested__c);
        Assert.areEqual('Awaiting Triage',          created.Status__c);
        Assert.areEqual(Date.today().addDays(30),   created.Effective_Date__c);
    }

    @isTest
    static void testCreateSubmissionMinimalFields() {
        CreateSubmissionFromEmail.CreateSubmissionInput input = new CreateSubmissionFromEmail.CreateSubmissionInput();
        input.insuredName    = 'Minimal Corp';
        input.lineOfBusiness = 'WC';

        Test.startTest();
        List<CreateSubmissionFromEmail.CreateSubmissionOutput> outputs =
            CreateSubmissionFromEmail.createSubmission(
                new List<CreateSubmissionFromEmail.CreateSubmissionInput>{ input }
            );
        Test.stopTest();

        Assert.areEqual(1, outputs.size());
        Assert.isNotNull(outputs[0].submissionId);

        Submission__c created = [
            SELECT Insured_Name__c, Lines_Requested__c, Status__c
            FROM   Submission__c
            WHERE  Id = :outputs[0].submissionId
        ];

        Assert.areEqual('Minimal Corp',    created.Insured_Name__c);
        Assert.areEqual('WC',              created.Lines_Requested__c);
        Assert.areEqual('Awaiting Triage', created.Status__c);
    }
}