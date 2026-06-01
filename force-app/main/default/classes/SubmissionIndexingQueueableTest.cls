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

    // ── With files: one Submission_Document__c bridge record per attached file ──
    //
    // No Data Cloud callout happens here — the CRM connector syncs the records
    // (and the underlying files) into Data Cloud on its own schedule. The records
    // are left in their default 'Pending' status purely for later matching.

    @IsTest
    static void execute_withFiles_createsBridgeRecords() {
        Submission__c sub = makeSubmission();
        attachFile(sub.Id, 'acord125.pdf',  Blob.valueOf('%PDF acord content'));
        attachFile(sub.Id, 'loss_runs.pdf', Blob.valueOf('%PDF loss run content'));

        Test.startTest();
        System.enqueueJob(new SubmissionIndexingQueueable(sub.Id));
        Test.stopTest();

        List<Submission_Document__c> docs = [
            SELECT Document_Name__c, Document_Type__c, Indexing_Status__c
            FROM   Submission_Document__c
            WHERE  Submission__c = :sub.Id
            ORDER BY Document_Name__c
        ];
        Assert.areEqual(2, docs.size(), 'One document record per attached file');
        Assert.areEqual('ACORD 125', docs[0].Document_Type__c, 'acord125.pdf maps to ACORD 125');
        Assert.areEqual('Loss Runs', docs[1].Document_Type__c, 'loss_runs.pdf maps to Loss Runs');
    }

    // ── No files: no bridge records are created ────────────────────────────────

    @IsTest
    static void execute_noFiles_createsNoBridgeRecords() {
        Submission__c sub = makeSubmission();

        Test.startTest();
        System.enqueueJob(new SubmissionIndexingQueueable(sub.Id));
        Test.stopTest();

        Integer docCount = [
            SELECT COUNT() FROM Submission_Document__c WHERE Submission__c = :sub.Id
        ];
        Assert.areEqual(0, docCount, 'No document records when no files attached');
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
}
