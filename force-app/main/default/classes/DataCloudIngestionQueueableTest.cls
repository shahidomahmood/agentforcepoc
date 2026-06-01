@IsTest
private class DataCloudIngestionQueueableTest {

    static Submission__c makeSubmission() {
        Submission__c sub = new Submission__c(Name = '20240524-Smith-Submission');
        insert sub;
        return sub;
    }

    static Id attachFile(Id parentId, String fileName, Blob content) {
        ContentVersion cv = new ContentVersion(
            Title                  = fileName,
            PathOnClient           = fileName,
            VersionData            = content,
            FirstPublishLocationId = parentId
        );
        insert cv;
        return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
    }

    static Submission_Document__c makeDocRecord(Id submissionId, Id contentDocId, String fileName) {
        Submission_Document__c doc = new Submission_Document__c(
            Name                   = fileName,
            Submission__c          = submissionId,
            Content_Document_Id__c = contentDocId,
            Document_Name__c       = fileName,
            Document_Type__c       = 'ACORD 125',
            File_Extension__c      = 'pdf',
            Indexing_Status__c     = 'Pending'
        );
        insert doc;
        return doc;
    }

    // ── Happy path ────────────────────────────────────────────────────────────

    @IsTest
    static void execute_success_marksDocIndexedAndSubmissionIndexed() {
        Submission__c sub = makeSubmission();
        Id cdId = attachFile(sub.Id, 'acord125.pdf', Blob.valueOf('%PDF acord content'));
        Submission_Document__c doc = makeDocRecord(sub.Id, cdId, 'acord125.pdf');

        Test.setMock(HttpCalloutMock.class, new MockSuccess());

        Test.startTest();
        System.enqueueJob(new DataCloudIngestionQueueable(new List<Id>{ doc.Id }, sub.Id));
        Test.stopTest();

        Submission_Document__c updatedDoc = [
            SELECT Indexing_Status__c, Data_Cloud_Document_Id__c, Error_Message__c
            FROM   Submission_Document__c WHERE Id = :doc.Id
        ];
        Assert.areEqual('Indexed', updatedDoc.Indexing_Status__c,
            'Document should be Indexed. Error: ' + updatedDoc.Error_Message__c);
        Assert.areEqual('req-test-001', updatedDoc.Data_Cloud_Document_Id__c);
        Assert.isNull(updatedDoc.Error_Message__c);

        Submission__c updatedSub = [SELECT Indexing_Status__c FROM Submission__c WHERE Id = :sub.Id];
        Assert.areEqual('Indexed', updatedSub.Indexing_Status__c);
    }

    @IsTest
    static void execute_multipleDocs_allIndexed() {
        Submission__c sub = makeSubmission();
        Id cdId1 = attachFile(sub.Id, 'acord125.pdf',  Blob.valueOf('%PDF acord'));
        Id cdId2 = attachFile(sub.Id, 'loss_runs.pdf', Blob.valueOf('%PDF loss'));
        Submission_Document__c doc1 = makeDocRecord(sub.Id, cdId1, 'acord125.pdf');
        Submission_Document__c doc2 = makeDocRecord(sub.Id, cdId2, 'loss_runs.pdf');

        Test.setMock(HttpCalloutMock.class, new MockSuccess());

        Test.startTest();
        System.enqueueJob(new DataCloudIngestionQueueable(
            new List<Id>{ doc1.Id, doc2.Id }, sub.Id
        ));
        Test.stopTest();

        for (Submission_Document__c d : [
            SELECT Indexing_Status__c FROM Submission_Document__c WHERE Id IN (:doc1.Id, :doc2.Id)
        ]) {
            Assert.areEqual('Indexed', d.Indexing_Status__c);
        }
        Submission__c updatedSub = [SELECT Indexing_Status__c FROM Submission__c WHERE Id = :sub.Id];
        Assert.areEqual('Indexed', updatedSub.Indexing_Status__c);
    }

    // ── Callout failure ───────────────────────────────────────────────────────

    @IsTest
    static void execute_calloutError_marksDocAndSubmissionFailed() {
        Submission__c sub = makeSubmission();
        Id cdId = attachFile(sub.Id, 'acord125.pdf', Blob.valueOf('%PDF content'));
        Submission_Document__c doc = makeDocRecord(sub.Id, cdId, 'acord125.pdf');

        Test.setMock(HttpCalloutMock.class, new MockError());

        Test.startTest();
        System.enqueueJob(new DataCloudIngestionQueueable(new List<Id>{ doc.Id }, sub.Id));
        Test.stopTest();

        Submission_Document__c updatedDoc = [
            SELECT Indexing_Status__c, Error_Message__c
            FROM   Submission_Document__c WHERE Id = :doc.Id
        ];
        Assert.areEqual('Failed', updatedDoc.Indexing_Status__c);
        Assert.isTrue(String.isNotBlank(updatedDoc.Error_Message__c));

        Submission__c updatedSub = [SELECT Indexing_Status__c FROM Submission__c WHERE Id = :sub.Id];
        Assert.areEqual('Failed', updatedSub.Indexing_Status__c);
    }

    // ── Missing ContentVersion ────────────────────────────────────────────────

    @IsTest
    static void execute_noContentVersion_marksDocumentFailed() {
        Submission__c sub = makeSubmission();
        // Blank Content_Document_Id__c → no ContentVersion to find
        Submission_Document__c doc = new Submission_Document__c(
            Name               = 'orphan.pdf',
            Submission__c      = sub.Id,
            Document_Name__c   = 'orphan.pdf',
            Document_Type__c   = 'Other',
            File_Extension__c  = 'pdf',
            Indexing_Status__c = 'Pending'
        );
        insert doc;

        Test.setMock(HttpCalloutMock.class, new MockSuccess());

        Test.startTest();
        System.enqueueJob(new DataCloudIngestionQueueable(new List<Id>{ doc.Id }, sub.Id));
        Test.stopTest();

        Submission_Document__c updated = [
            SELECT Indexing_Status__c, Error_Message__c
            FROM   Submission_Document__c WHERE Id = :doc.Id
        ];
        Assert.areEqual('Failed', updated.Indexing_Status__c);
        Assert.isTrue(updated.Error_Message__c.contains('ContentVersion not found'));
    }

    // ── Empty list ────────────────────────────────────────────────────────────

    @IsTest
    static void execute_emptyList_doesNothing() {
        Test.startTest();
        System.enqueueJob(new DataCloudIngestionQueueable(new List<Id>()));
        Test.stopTest();
        Assert.isTrue(true, 'Empty list should execute without error');
    }

    // ── PushToDataCloudAction ─────────────────────────────────────────────────

    @IsTest
    static void push_validIds_enqueuesWithoutError() {
        Submission__c sub = makeSubmission();
        Id cdId = attachFile(sub.Id, 'acord125.pdf', Blob.valueOf('%PDF acord'));
        Submission_Document__c doc = makeDocRecord(sub.Id, cdId, 'acord125.pdf');

        Test.setMock(HttpCalloutMock.class, new MockSuccess());

        Test.startTest();
        PushToDataCloudAction.push(new List<String>{ doc.Id });
        Test.stopTest();

        Assert.isTrue(true, 'PushToDataCloudAction.push should enqueue without throwing');
    }

    @IsTest
    static void push_nullOrEmpty_doesNothing() {
        Test.startTest();
        PushToDataCloudAction.push(null);
        PushToDataCloudAction.push(new List<String>());
        Test.stopTest();
        Assert.isTrue(true, 'Null or empty input should not throw');
    }

    // ── Mocks ─────────────────────────────────────────────────────────────────

    private class MockSuccess implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(202);
            res.setBody('{"requestId":"req-test-001"}');
            return res;
        }
    }

    private class MockError implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"error":"Internal Server Error"}');
            return res;
        }
    }
}
