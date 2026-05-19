public with sharing class SubmissionsInboxController {

    @AuraEnabled(cacheable=true)
    public static List<Submission_Email__c> getSubmissionEmails() {
        return [
            SELECT Id, From_Name__c, From_Email__c, Subject__c,
                   Received_Date__c, Attachment_Count__c, Status__c
            FROM   Submission_Email__c
            ORDER BY Received_Date__c DESC NULLS LAST
            LIMIT  200
        ];
    }
}