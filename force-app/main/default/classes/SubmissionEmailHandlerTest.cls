@IsTest
private class SubmissionEmailHandlerTest {

    @IsTest
    static void testHandlerCreatesRecordAndStoresFiles() {
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        email.fromAddress   = 'broker@example.com';
        email.fromName      = 'Test Broker';
        email.subject       = 'WC Submission - Test Corp';
        email.plainTextBody = 'Please process this submission.';

        Messaging.InboundEmail.BinaryAttachment att = new Messaging.InboundEmail.BinaryAttachment();
        att.filename        = 'loss_run.pdf';
        att.body            = Blob.valueOf('fake pdf content');
        att.mimeTypeSubType = 'pdf';
        email.binaryAttachments = new List<Messaging.InboundEmail.BinaryAttachment>{ att };

        Messaging.InboundEnvelope envelope = new Messaging.InboundEnvelope();
        envelope.toAddress = 'submissions@example.com';

        Test.startTest();
        SubmissionEmailHandler handler = new SubmissionEmailHandler();
        Messaging.InboundEmailResult result = handler.handleInboundEmail(email, envelope);
        Test.stopTest();

        System.assert(result.success, 'Handler should return success=true');

        List<Submission_Email__c> records = [
            SELECT Id, From_Email__c, Subject__c, Attachment_Count__c, Status__c
            FROM Submission_Email__c
        ];
        System.assertEquals(1, records.size(), 'One Submission_Email__c should be created');
        System.assertEquals('broker@example.com', records[0].From_Email__c);
        System.assertEquals('WC Submission - Test Corp', records[0].Subject__c);
        System.assertEquals(1, records[0].Attachment_Count__c);
        System.assertEquals('Received', records[0].Status__c);

        List<ContentDocumentLink> links = [
            SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :records[0].Id
        ];
        System.assertEquals(1, links.size(), 'PDF attachment should be stored and linked to the inbox record');
    }

    @IsTest
    static void testHandlerSucceedsWithNoAttachments() {
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        email.fromAddress   = 'broker@example.com';
        email.fromName      = 'No-Att Broker';
        email.subject       = 'Simple WC Email';
        email.plainTextBody = 'No attachments here.';

        Messaging.InboundEnvelope envelope = new Messaging.InboundEnvelope();

        Test.startTest();
        SubmissionEmailHandler handler = new SubmissionEmailHandler();
        Messaging.InboundEmailResult result = handler.handleInboundEmail(email, envelope);
        Test.stopTest();

        System.assert(result.success, 'Handler should succeed when there are no attachments');

        List<Submission_Email__c> records = [SELECT Id FROM Submission_Email__c];
        System.assertEquals(1, records.size(), 'One record should be created');

        List<ContentDocumentLink> links = [
            SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :records[0].Id
        ];
        System.assertEquals(0, links.size(), 'No files should be created');
    }
}