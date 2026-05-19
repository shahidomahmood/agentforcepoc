@IsTest
private class SubmissionEmailServiceTest {

    @IsTest
    static void testCreateFromEmailPlainText() {
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        email.fromAddress = 'broker@example.com';
        email.fromName    = 'John Broker';
        email.subject     = 'WC Submission - Acme Corp';
        email.plainTextBody = 'Please see attached submission for Acme Corp.';

        Test.startTest();
        Submission_Email__c result = SubmissionEmailService.createFromEmail(email);
        Test.stopTest();

        System.assertNotEquals(null, result.Id, 'Record should be inserted');
        Submission_Email__c queried = [
            SELECT From_Email__c, From_Name__c, Subject__c, Body__c,
                   Status__c, Attachment_Count__c
            FROM Submission_Email__c
            WHERE Id = :result.Id
        ];
        System.assertEquals('broker@example.com', queried.From_Email__c);
        System.assertEquals('John Broker',         queried.From_Name__c);
        System.assertEquals('WC Submission - Acme Corp', queried.Subject__c);
        System.assertEquals('Please see attached submission for Acme Corp.', queried.Body__c);
        System.assertEquals('Received', queried.Status__c);
        System.assertEquals(0, queried.Attachment_Count__c);
    }

    @IsTest
    static void testCreateFromEmailFallsBackToHtml() {
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        email.fromAddress = 'broker@example.com';
        email.fromName    = 'Jane Broker';
        email.subject     = 'WC Submission';
        email.htmlBody    = '<p>HTML body content</p>';

        Test.startTest();
        Submission_Email__c result = SubmissionEmailService.createFromEmail(email);
        Test.stopTest();

        Submission_Email__c queried = [SELECT Body__c FROM Submission_Email__c WHERE Id = :result.Id];
        System.assertEquals('<p>HTML body content</p>', queried.Body__c);
    }

    @IsTest
    static void testAttachmentCountCaptured() {
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        email.fromAddress   = 'broker@example.com';
        email.fromName      = 'Bob Broker';
        email.subject       = 'WC Submission with Attachments';
        email.plainTextBody = 'See attachments.';

        Messaging.InboundEmail.BinaryAttachment att = new Messaging.InboundEmail.BinaryAttachment();
        att.filename        = 'loss_run.pdf';
        att.body            = Blob.valueOf('fake pdf content');
        att.mimeTypeSubType = 'pdf';
        email.binaryAttachments = new List<Messaging.InboundEmail.BinaryAttachment>{ att };

        Test.startTest();
        Submission_Email__c result = SubmissionEmailService.createFromEmail(email);
        Test.stopTest();

        Submission_Email__c queried = [SELECT Attachment_Count__c FROM Submission_Email__c WHERE Id = :result.Id];
        System.assertEquals(1, queried.Attachment_Count__c);
    }
}