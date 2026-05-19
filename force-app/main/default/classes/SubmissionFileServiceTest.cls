@IsTest
private class SubmissionFileServiceTest {

    static Submission_Email__c makeEmailRecord() {
        Submission_Email__c rec = new Submission_Email__c(
            From_Email__c    = 'broker@example.com',
            Subject__c       = 'Test Email',
            Status__c        = 'Received',
            Received_Date__c = DateTime.now()
        );
        insert rec;
        return rec;
    }

    @IsTest
    static void testStoreBinaryAttachment() {
        Submission_Email__c emailRecord = makeEmailRecord();

        Messaging.InboundEmail.BinaryAttachment att = new Messaging.InboundEmail.BinaryAttachment();
        att.filename        = 'loss_run.pdf';
        att.body            = Blob.valueOf('fake pdf content');
        att.mimeTypeSubType = 'pdf';

        Test.startTest();
        SubmissionFileService.storeAttachments(
            new List<Messaging.InboundEmail.BinaryAttachment>{ att },
            null,
            emailRecord.Id
        );
        Test.stopTest();

        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :emailRecord.Id
        ];
        System.assertEquals(1, links.size(), 'Binary attachment should be linked to the email record');

        ContentVersion cv = [
            SELECT Title, PathOnClient
            FROM ContentVersion
            WHERE ContentDocumentId = :links[0].ContentDocumentId
        ];
        System.assertEquals('loss_run.pdf', cv.Title);
        System.assertEquals('loss_run.pdf', cv.PathOnClient);
    }

    @IsTest
    static void testStoreTextAttachment() {
        Submission_Email__c emailRecord = makeEmailRecord();

        Messaging.InboundEmail.TextAttachment att = new Messaging.InboundEmail.TextAttachment();
        att.filename = 'notes.txt';
        att.body     = 'Some text notes here';

        Test.startTest();
        SubmissionFileService.storeAttachments(
            null,
            new List<Messaging.InboundEmail.TextAttachment>{ att },
            emailRecord.Id
        );
        Test.stopTest();

        List<ContentDocumentLink> links = [
            SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :emailRecord.Id
        ];
        System.assertEquals(1, links.size(), 'Text attachment should be stored as a file');
    }

    @IsTest
    static void testMultipleAttachments() {
        Submission_Email__c emailRecord = makeEmailRecord();

        Messaging.InboundEmail.BinaryAttachment att1 = new Messaging.InboundEmail.BinaryAttachment();
        att1.filename = 'acord.pdf';
        att1.body     = Blob.valueOf('acord pdf');
        att1.mimeTypeSubType = 'pdf';

        Messaging.InboundEmail.BinaryAttachment att2 = new Messaging.InboundEmail.BinaryAttachment();
        att2.filename = 'loss_run.pdf';
        att2.body     = Blob.valueOf('loss run pdf');
        att2.mimeTypeSubType = 'pdf';

        Test.startTest();
        SubmissionFileService.storeAttachments(
            new List<Messaging.InboundEmail.BinaryAttachment>{ att1, att2 },
            null,
            emailRecord.Id
        );
        Test.stopTest();

        Integer linkCount = [
            SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :emailRecord.Id
        ];
        System.assertEquals(2, linkCount, 'Both attachments should be stored and linked');
    }

    @IsTest
    static void testNoAttachmentsIsNoOp() {
        Submission_Email__c emailRecord = makeEmailRecord();

        Test.startTest();
        SubmissionFileService.storeAttachments(null, null, emailRecord.Id);
        Test.stopTest();

        Integer linkCount = [
            SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :emailRecord.Id
        ];
        System.assertEquals(0, linkCount, 'No files should be created when there are no attachments');
    }
}