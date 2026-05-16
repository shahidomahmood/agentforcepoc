public with sharing class CreateSubmissionFromEmail {

    @InvocableMethod(
        label='Create Submission from Email'
        description='Extracts key fields from an inbound broker email and creates a new Submission__c record set to Awaiting Triage. Provide sender name, sender email, broker agency name, insured name, line of business, and desired effective date as extracted from the email subject or body.'
        category='Submission Management'
    )
    public static List<CreateSubmissionOutput> createSubmission(List<CreateSubmissionInput> inputs) {
        List<Submission__c> toInsert = new List<Submission__c>();

        for (CreateSubmissionInput input : inputs) {
            toInsert.add(new Submission__c(
                Sender_Name__c        = input.senderName,
                Sender_Email__c       = input.senderEmail,
                Broker_Agency_Name__c = input.brokerAgencyName,
                Insured_Name__c       = input.insuredName,
                Lines_Requested__c    = input.lineOfBusiness,
                Effective_Date__c     = input.effectiveDate,
                Status__c             = 'Awaiting Triage'
            ));
        }

        insert toInsert;

        List<CreateSubmissionOutput> outputs = new List<CreateSubmissionOutput>();
        for (Submission__c sub : toInsert) {
            CreateSubmissionOutput out = new CreateSubmissionOutput();
            out.submissionId = sub.Id;
            outputs.add(out);
        }
        return outputs;
    }

    public class CreateSubmissionInput {

        @InvocableVariable(
            label='Sender Name'
            description='Full name of the broker or agent who sent the email'
            required=false
        )
        public String senderName;

        @InvocableVariable(
            label='Sender Email'
            description='Email address of the sender'
            required=false
        )
        public String senderEmail;

        @InvocableVariable(
            label='Broker Agency Name'
            description='Name of the brokerage or agency submitting the risk'
            required=false
        )
        public String brokerAgencyName;

        @InvocableVariable(
            label='Insured Name'
            description='Name of the insured business extracted from the email subject or body'
            required=false
        )
        public String insuredName;

        @InvocableVariable(
            label='Line of Business'
            description='Insurance line of business (e.g. WC for Workers Compensation)'
            required=false
        )
        public String lineOfBusiness;

        @InvocableVariable(
            label='Desired Effective Date'
            description='Requested policy effective date parsed from the email'
            required=false
        )
        public Date effectiveDate;
    }

    public class CreateSubmissionOutput {

        @InvocableVariable(
            label='Submission Record ID'
            description='Salesforce ID of the newly created Submission__c record'
        )
        public String submissionId;
    }
}