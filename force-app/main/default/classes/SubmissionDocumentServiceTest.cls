@IsTest
private class SubmissionDocumentServiceTest {

    static Submission__c makeSubmission() {
        Submission__c sub = new Submission__c(Name = 'Test-Sub');
        insert sub;
        return sub;
    }

    static Id attachFile(Id parentId, String fileName) {
        ContentVersion cv = new ContentVersion(
            Title                  = fileName,
            PathOnClient           = fileName,
            VersionData            = Blob.valueOf('dummy content'),
            FirstPublishLocationId = parentId
        );
        insert cv;
        return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
    }

    @IsTest
    static void createDocumentRecords_createsOnePerAttachment() {
        Submission__c sub = makeSubmission();
        attachFile(sub.Id, 'acord125.pdf');
        attachFile(sub.Id, 'loss_run_history.pdf');

        Test.startTest();
        List<Submission_Document__c> docs = SubmissionDocumentService.createDocumentRecords(sub.Id);
        Test.stopTest();

        Assert.areEqual(2, docs.size(), 'Should create one record per linked file');

        List<Submission_Document__c> saved = [
            SELECT Document_Name__c, Indexing_Status__c, Document_Type__c
            FROM   Submission_Document__c
            WHERE  Submission__c = :sub.Id
            ORDER BY Document_Name__c
        ];
        Assert.areEqual(2, saved.size());
        Assert.areEqual('Pending', saved[0].Indexing_Status__c);
        Assert.areEqual('Pending', saved[1].Indexing_Status__c);
    }

    @IsTest
    static void createDocumentRecords_noFiles_returnsEmpty() {
        Submission__c sub = makeSubmission();

        Test.startTest();
        List<Submission_Document__c> docs = SubmissionDocumentService.createDocumentRecords(sub.Id);
        Test.stopTest();

        Assert.areEqual(0, docs.size(), 'Should return empty list when no files attached');
    }

    @IsTest
    static void createDocumentRecords_isIdempotent() {
        Submission__c sub = makeSubmission();
        attachFile(sub.Id, 'acord125.pdf');

        Test.startTest();
        SubmissionDocumentService.createDocumentRecords(sub.Id);
        SubmissionDocumentService.createDocumentRecords(sub.Id);
        Test.stopTest();

        Integer count = [
            SELECT COUNT() FROM Submission_Document__c WHERE Submission__c = :sub.Id
        ];
        Assert.areEqual(1, count, 'Upsert on ContentDocumentId should not create duplicates');
    }

    @IsTest
    static void inferDocumentType_detectsAcord125() {
        Assert.areEqual('ACORD 125', SubmissionDocumentService.inferDocumentType('acord125.pdf'));
        Assert.areEqual('ACORD 125', SubmissionDocumentService.inferDocumentType('ACORD 125 Application.pdf'));
    }

    @IsTest
    static void inferDocumentType_detectsLossRuns() {
        Assert.areEqual('Loss Runs', SubmissionDocumentService.inferDocumentType('loss_run_history.pdf'));
        Assert.areEqual('Loss Runs', SubmissionDocumentService.inferDocumentType('Loss Runs 2023.pdf'));
    }

    @IsTest
    static void inferDocumentType_defaultsToOther() {
        Assert.areEqual('Other', SubmissionDocumentService.inferDocumentType('miscellaneous.docx'));
        Assert.areEqual('Other', SubmissionDocumentService.inferDocumentType(null));
        Assert.areEqual('Other', SubmissionDocumentService.inferDocumentType(''));
    }
}
