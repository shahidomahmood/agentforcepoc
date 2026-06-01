@IsTest
private class DataCloudIngestionServiceTest {

    static Submission__c makeSubmission() {
        Submission__c sub = new Submission__c(Name = '20240524-Smith-Submission');
        insert sub;
        return sub;
    }

    static DataCloudIngestionService.DocumentPayload makePayload(
        Submission__c sub,
        String contentDocId,
        String fileName,
        String fileExt
    ) {
        Submission_Document__c doc = new Submission_Document__c(
            Name                   = fileName,
            Submission__c          = sub.Id,
            Content_Document_Id__c = contentDocId,
            Document_Name__c       = fileName,
            Document_Type__c       = 'ACORD 125',
            File_Extension__c      = fileExt,
            Indexing_Status__c     = 'Pending'
        );
        insert doc;

        DataCloudIngestionService.DocumentPayload p = new DataCloudIngestionService.DocumentPayload();
        p.doc      = doc;
        p.fileSize = 32768L;
        p.mimeType = DataCloudIngestionService.getMimeType(fileExt);
        return p;
    }

    @IsTest
    static void pushDocuments_successResponse_returnsSuccess() {
        Submission__c sub = makeSubmission();
        DataCloudIngestionService.DocumentPayload p =
            makePayload(sub, '0690000000000001AA', 'acord125.pdf', 'pdf');

        Test.setMock(HttpCalloutMock.class, new MockSuccess());

        Test.startTest();
        List<DataCloudIngestionService.IngestionResult> results =
            DataCloudIngestionService.pushDocuments(
                new List<DataCloudIngestionService.DocumentPayload>{ p },
                sub.Name
            );
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.isTrue(results[0].success, 'Should report success for 202 response');
        Assert.areEqual('req-abc-001', results[0].requestId);
        Assert.isNull(results[0].errorMessage);
    }

    @IsTest
    static void pushDocuments_errorResponse_returnsFailure() {
        Submission__c sub = makeSubmission();
        DataCloudIngestionService.DocumentPayload p =
            makePayload(sub, '0690000000000002BB', 'loss_runs.pdf', 'pdf');

        Test.setMock(HttpCalloutMock.class, new MockError());

        Test.startTest();
        List<DataCloudIngestionService.IngestionResult> results =
            DataCloudIngestionService.pushDocuments(
                new List<DataCloudIngestionService.DocumentPayload>{ p },
                sub.Name
            );
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.isFalse(results[0].success, 'Should report failure for 500 response');
        Assert.isTrue(results[0].errorMessage.startsWith('HTTP 500'));
    }

    @IsTest
    static void pushDocuments_networkFailure_returnsFailure() {
        Submission__c sub = makeSubmission();
        DataCloudIngestionService.DocumentPayload p =
            makePayload(sub, '0690000000000003CC', 'acord125.pdf', 'pdf');

        Test.setMock(HttpCalloutMock.class, new MockNetworkFailure());

        Test.startTest();
        List<DataCloudIngestionService.IngestionResult> results =
            DataCloudIngestionService.pushDocuments(
                new List<DataCloudIngestionService.DocumentPayload>{ p },
                sub.Name
            );
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.isFalse(results[0].success);
        Assert.isTrue(results[0].errorMessage.startsWith('Callout failed'));
    }

    @IsTest
    static void pushDocuments_payloadShape_containsExpectedFields() {
        Submission__c sub = makeSubmission();
        DataCloudIngestionService.DocumentPayload p =
            makePayload(sub, '0690000000000004DD', 'acord125.pdf', 'pdf');

        MockCapture capture = new MockCapture(new MockSuccess());
        Test.setMock(HttpCalloutMock.class, capture);

        Test.startTest();
        DataCloudIngestionService.pushDocuments(
            new List<DataCloudIngestionService.DocumentPayload>{ p },
            sub.Name
        );
        Test.stopTest();

        Assert.isTrue(capture.capturedBody.contains('"DocumentId"'),    'Payload must contain DocumentId');
        Assert.isTrue(capture.capturedBody.contains('"SubmissionId"'),  'Payload must contain SubmissionId');
        Assert.isTrue(capture.capturedBody.contains('"SourceSystem"'),  'Payload must contain SourceSystem');
        Assert.isTrue(capture.capturedBody.contains('"FileSize"'),      'Payload must contain FileSize');
        Assert.isTrue(capture.capturedBody.contains('"LastModified"'),  'Payload must contain LastModified');
    }

    @IsTest
    static void pushDocuments_multipleDocs_allGetResults() {
        Submission__c sub = makeSubmission();
        DataCloudIngestionService.DocumentPayload p1 =
            makePayload(sub, '0690000000000005EE', 'acord125.pdf', 'pdf');
        DataCloudIngestionService.DocumentPayload p2 =
            makePayload(sub, '0690000000000006FF', 'loss_runs.pdf', 'pdf');

        Test.setMock(HttpCalloutMock.class, new MockSuccess());

        Test.startTest();
        List<DataCloudIngestionService.IngestionResult> results =
            DataCloudIngestionService.pushDocuments(
                new List<DataCloudIngestionService.DocumentPayload>{ p1, p2 },
                sub.Name
            );
        Test.stopTest();

        Assert.areEqual(2, results.size(), 'Should return one result per document');
        for (DataCloudIngestionService.IngestionResult r : results) {
            Assert.isTrue(r.success);
        }
    }

    @IsTest
    static void getMimeType_knownExtensions() {
        Assert.areEqual('application/pdf',    DataCloudIngestionService.getMimeType('pdf'));
        Assert.areEqual('application/pdf',    DataCloudIngestionService.getMimeType('PDF'));
        Assert.areEqual('text/csv',           DataCloudIngestionService.getMimeType('csv'));
        Assert.areEqual('text/plain',         DataCloudIngestionService.getMimeType('txt'));
        Assert.areEqual('application/octet-stream', DataCloudIngestionService.getMimeType('xyz'));
        Assert.areEqual('application/octet-stream', DataCloudIngestionService.getMimeType(null));
    }

    // ── Mocks ────────────────────────────────────────────────────────────────

    private class MockSuccess implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(202);
            res.setBody('{"requestId":"req-abc-001","accepted":true}');
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

    // Renamed from MockCalloutException — Apex treats any class named *Exception as an Exception subclass
    private class MockNetworkFailure implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            CalloutException e = new CalloutException();
            e.setMessage('Connection refused');
            throw e;
        }
    }

    // static fields are illegal on inner classes in Apex; capturedBody is an instance field instead
    private class MockCapture implements HttpCalloutMock {
        String capturedBody;
        private final HttpCalloutMock delegate; // 'inner' is a reserved identifier in Apex
        MockCapture(HttpCalloutMock delegate) { this.delegate = delegate; }
        public HttpResponse respond(HttpRequest req) {
            capturedBody = req.getBody();
            return delegate.respond(req);
        }
    }
}
