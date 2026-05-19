public with sharing class SubmissionEmailService {

    public static Submission_Email__c createFromEmail(Messaging.InboundEmail email) {
        Integer attachmentCount = 0;
        if (email.binaryAttachments != null) {
            attachmentCount += email.binaryAttachments.size();
        }
        if (email.textAttachments != null) {
            attachmentCount += email.textAttachments.size();
        }

        String body = String.isNotBlank(email.plainTextBody)
            ? email.plainTextBody
            : email.htmlBody;

        Submission_Email__c record = new Submission_Email__c(
            From_Email__c       = email.fromAddress,
            From_Name__c        = email.fromName,
            Subject__c          = email.subject,
            Body__c             = body,
            Received_Date__c    = DateTime.now(),
            Status__c           = 'Received',
            Attachment_Count__c = attachmentCount
        );
        insert record;
        return record;
    }
}