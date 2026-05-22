public with sharing class ProcessSubmissionEmailAction {

    @InvocableMethod(
        label='Process Submission Email'
        description='Creates a preliminary Submission__c record from an inbound broker email, links any attachments, and marks the email as Processed.'
        category='Submission Management'
    )
    public static List<Output> process(List<Input> inputs) {
        List<Output> results = new List<Output>();
        for (Input inp : inputs) {
            Output out = new Output();
            out.submissionId = doProcess(inp.submissionEmailId);
            results.add(out);
        }
        return results;
    }

    @AuraEnabled
    public static String processEmail(String submissionEmailId) {
        return doProcess(submissionEmailId);
    }

    private static String doProcess(String emailId) {
        Submission_Email__c email = [
            SELECT Id, From_Name__c, From_Email__c, Body__c, Received_Date__c, Status__c
            FROM   Submission_Email__c
            WHERE  Id = :emailId
            LIMIT  1
        ];

        String lastName = 'Unknown';
        if (String.isNotBlank(email.From_Name__c)) {
            List<String> parts = email.From_Name__c.trim().split('\\s+');
            lastName = parts[parts.size() - 1];
        }
        String dateStr = email.Received_Date__c != null
            ? email.Received_Date__c.format('yyyyMMdd')
            : String.valueOf(Date.today()).replace('-', '');
        String subName = dateStr + '-' + lastName + '-Submission';

        Submission__c sub = new Submission__c(
            Name                = subName,
            Source__c           = 'Email',
            Body__c             = email.Body__c,
            Received_Date__c    = email.Received_Date__c,
            Submission_Email__c = email.Id
        );
        insert sub;

        List<ContentDocumentLink> emailLinks = [
            SELECT ContentDocumentId
            FROM   ContentDocumentLink
            WHERE  LinkedEntityId = :emailId
        ];

        if (!emailLinks.isEmpty()) {
            List<ContentDocumentLink> subLinks = new List<ContentDocumentLink>();
            for (ContentDocumentLink cdl : emailLinks) {
                subLinks.add(new ContentDocumentLink(
                    ContentDocumentId = cdl.ContentDocumentId,
                    LinkedEntityId    = sub.Id,
                    ShareType         = 'V',
                    Visibility        = 'AllUsers'
                ));
            }
            insert subLinks;
        }

        email.Status__c = 'Processed';
        update email;

        return sub.Id;
    }

    public class Input {
        @InvocableVariable(
            label='Submission Email ID'
            description='Salesforce record ID of the Submission_Email__c to process'
            required=true
        )
        public String submissionEmailId;
    }

    public class Output {
        @InvocableVariable(
            label='Submission Record ID'
            description='Salesforce record ID of the newly created Submission__c record'
        )
        public String submissionId;
    }
}
