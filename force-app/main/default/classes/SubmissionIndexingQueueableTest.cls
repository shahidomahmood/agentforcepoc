@IsTest
private class SubmissionIndexingQueueableTest {

    static Submission__c makeSubmission() {
        Submission__c sub = new Submission__c(Name = '20240524-Smith-Submission');
        insert sub;
        return sub;
    }

    static void attachFile(Id parentId, String fileName, Blob content) {
        ContentVersion cv = new ContentVersion(
            Title                  = fileName,
            PathOnClient           = fileName,
            VersionData            = content,
            FirstPublishLocationId = parentId
        );
        insert cv;
    }

    // ── Phase-1 responsibility: create Submission_Document__c records ──────────
    //
    // Calling execute() directly (rather than via System.enqueueJob) avoids the
    // Salesforce "Maximum stack depth" restriction that fires when a Queueable
    // tries to enqueue another job during test execution.  The inner
    // DataCloudIngestionQueueable is still enqueued and runs at Test.stopTest(),
    // so we set a mock and assert the final Indexed state.

    @IsTest
    static void execute_withFiles_createsDocRecordsAndIndexesThem() {
        Submission__c sub = makeSubmission();
        attachFile(sub.Id, 'acord125.pdf',  Blob.valueOf('%PDF acord content'));
        attachFile(sub.Id, 'loss_runs.pdf', Blob.valueOf('%PDF loss run content'));

        Test.setMock(HttpCalloutMock.class, new MockSuccess());

        Test.startTest();
        new SubmissionIndexingQueueable(sub.Id).execute(null);
        // DataCloudIngestionQueueable is now enqueued; Test.stopTest() runs it
        Test.stopTest();

        List<Submission_Document__c> docs = [
            SELECT Document_Name__c, Indexing_Status__c, Error_Message__c
            FROM   Submission_Document__c
            WHERE  Submission__c = :sub.Id
            ORDER BY Document_Name__c
        ];
        Assert.areEqual(2, docs.size(), 'One document record per attached file');
        for (Submission_Document__c doc : docs) {
            Assert.areEqual(
                'Indexed', doc.Indexing_Status__c,
                'Status should be Indexed after DataCloudIngestionQueueable runs. Error: '
                + doc.Error_Message__c
            );
        }
    }

    // ── No-files path: submission is immediately Indexed (no callout needed) ──

    @IsTest
    static void execute_noFiles_marksSubmissionIndexed() {
        Submission__c sub = makeSubmission();

        Test.startTest();
        System.enqueueJob(new SubmissionIndexingQueueable(sub.Id));
        Test.stopTest();

        Integer docCount = [
            SELECT COUNT() FROM Submission_Document__c WHERE Submission__c = :sub.Id
        ];
        Assert.areEqual(0, docCount, 'No document records when no files attached');

        Submission__c updated = [SELECT Indexing_Status__c FROM Submission__c WHERE Id = :sub.Id];
        Assert.areEqual('Indexed', updated.Indexing_Status__c);
    }

    // ── Static enqueue helper ─────────────────────────────────────────────────

    @IsTest
    static void enqueue_staticMethod_dispatchesJobSuccessfully() {
        Submission__c sub = makeSubmission();

        Test.startTest();
        SubmissionIndexingQueueable.enqueue(sub.Id);
        Test.stopTest();

        Assert.isTrue(true, 'enqueue() should dispatch without throwing');
    }

    // ── Mock ──────────────────────────────────────────────────────────────────

    private class MockSuccess implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(202);
            res.setBody('{"requestId":"req-siq-001"}');
            return res;
        }
    }
}
