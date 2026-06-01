public with sharing class SubmissionValidationAction {

    public class ValidationRequest {
        @InvocableVariable(required=true label='Submission ID')
        public String submissionId;
    }

    public class ValidationResult {
        @InvocableVariable(label='Success')
        public Boolean success;
        @InvocableVariable(label='Missing Item Count')
        public Integer missingCount;
        @InvocableVariable(label='Message')
        public String message;
    }

    @InvocableMethod(label='Validate Submission & Draft Email' description='Checks submission completeness against configured requirements and drafts a broker follow-up email')
    public static List<ValidationResult> validateInvocable(List<ValidationRequest> requests) {
        List<ValidationResult> results = new List<ValidationResult>();
        for (ValidationRequest req : requests) {
            ValidationResult res = new ValidationResult();
            try {
                res.missingCount = validateSubmission(req.submissionId);
                res.success = true;
                res.message = res.missingCount == 0 ? 'Submission is complete.' : res.missingCount + ' missing item(s) found.';
            } catch (Exception e) {
                res.success = false;
                res.message = e.getMessage();
            }
            results.add(res);
        }
        return results;
    }

    @AuraEnabled
    public static Integer validateSubmission(String submissionId) {
        // Load active requirements for the submission's line of business
        List<Submission_Requirement__mdt> allRequirements = [
            SELECT Label, Line_of_Business__c, Document_Type__c, Required_Field_API_Name__c,
                   Requirement_Type__c, Severity__c, Missing_Message__c, Sort_Order__c
            FROM   Submission_Requirement__mdt
            WHERE  Active__c = true
            ORDER BY Sort_Order__c ASC NULLS LAST
        ];

        // Build dynamic SOQL to include all field-type requirement fields
        Set<String> fieldsToQuery = new Set<String>{
            'Id', 'Name', 'Line_of_Business__c', 'Submission_Email__c',
            'Payroll__c', 'NAICS_Codes__c', 'Policy_Effective_Date__c',
            'Number_of_Employees__c', 'Insured_Name__c', 'Broker_Name__c'
        };
        for (Submission_Requirement__mdt req : allRequirements) {
            if (req.Requirement_Type__c == 'Field' && String.isNotBlank(req.Required_Field_API_Name__c)) {
                fieldsToQuery.add(req.Required_Field_API_Name__c);
            }
        }

        Submission__c sub = Database.query(
            'SELECT ' + String.join(new List<String>(fieldsToQuery), ', ') +
            ' FROM Submission__c WHERE Id = \'' + String.escapeSingleQuotes(submissionId) + '\' LIMIT 1'
        );

        String lob = String.isNotBlank(sub.Line_of_Business__c) ? sub.Line_of_Business__c : 'Workers Comp';

        // Filter requirements to this line of business
        List<Submission_Requirement__mdt> requirements = new List<Submission_Requirement__mdt>();
        for (Submission_Requirement__mdt req : allRequirements) {
            if (req.Line_of_Business__c == lob) {
                requirements.add(req);
            }
        }

        // Check document-type requirements: look for keyword match in attached file titles
        Set<String> attachedDocTitles = new Set<String>();
        if (!requirements.isEmpty()) {
            for (ContentDocumentLink cdl : [
                SELECT ContentDocument.Title
                FROM   ContentDocumentLink
                WHERE  LinkedEntityId = :submissionId
            ]) {
                attachedDocTitles.add(cdl.ContentDocument.Title.toUpperCase());
            }
        }

        // Evaluate each requirement
        List<Missing_Item__c> missingItems = new List<Missing_Item__c>();
        Integer sortIdx = 1;

        for (Submission_Requirement__mdt req : requirements) {
            Boolean isMissing = false;

            if (req.Requirement_Type__c == 'Field') {
                Object val = sub.get(req.Required_Field_API_Name__c);
                isMissing = (val == null || String.valueOf(val).trim() == '');
            } else if (req.Requirement_Type__c == 'Document') {
                String keyword = req.Document_Type__c.toUpperCase();
                isMissing = true;
                for (String title : attachedDocTitles) {
                    if (title.contains(keyword)) {
                        isMissing = false;
                        break;
                    }
                }
            }

            if (isMissing) {
                missingItems.add(new Missing_Item__c(
                    Submission__c      = sub.Id,
                    Missing_Message__c = req.Missing_Message__c,
                    Severity__c        = req.Severity__c,
                    Requirement_Type__c = req.Requirement_Type__c,
                    Sort_Order__c      = sortIdx++
                ));
            }
        }

        // Replace existing missing items for this submission
        delete [SELECT Id FROM Missing_Item__c WHERE Submission__c = :sub.Id];
        if (!missingItems.isEmpty()) {
            insert missingItems;
        }

        // Set completeness status
        String status = missingItems.isEmpty() ? 'Ready for Review' : 'Additional Information Required';

        // Draft broker email via Agentforce if there are missing items
        String emailDraft = '';
        if (!missingItems.isEmpty()) {
            emailDraft = generateEmailDraft(sub, missingItems, lob);
        }

        update new Submission__c(
            Id                    = sub.Id,
            Completeness_Status__c = status,
            Follow_Up_Email_Draft__c = emailDraft
        );

        return missingItems.size();
    }

    @AuraEnabled
    public static void sendFollowUpEmail(String submissionId, String emailBody) {
        sendFollowUpEmail(submissionId, emailBody, true);
    }

    @AuraEnabled
    public static void saveDraft(String submissionId, String emailBody) {
        sendFollowUpEmail(submissionId, emailBody, false);
    }

    private static void sendFollowUpEmail(String submissionId, String emailBody, Boolean doSend) {
        Submission__c sub = [
            SELECT Id, Name,
                   Submission_Email__r.From_Email__c
            FROM   Submission__c
            WHERE  Id = :submissionId
            LIMIT  1
        ];

        if (doSend) {
            if (String.isBlank(sub.Submission_Email__r.From_Email__c)) {
                throw new AuraHandledException('No broker email address found on the linked submission email.');
            }
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new List<String>{ sub.Submission_Email__r.From_Email__c });
            mail.setSubject('Additional Information Required: ' + sub.Name);
            mail.setPlainTextBody(emailBody);
            mail.setSaveAsActivity(true);
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
        }

        update new Submission__c(
            Id                       = sub.Id,
            Follow_Up_Email_Draft__c = emailBody
        );
    }

    private static String generateEmailDraft(Submission__c sub, List<Missing_Item__c> missingItems, String lob) {
        try {
            List<String> itemLines = new List<String>();
            for (Missing_Item__c item : missingItems) {
                itemLines.add('- [' + item.Severity__c + '] ' + item.Missing_Message__c);
            }
            String missingList = String.join(itemLines, '\n');

            String promptName = 'Submission_Follow_Up_Email';
            ConnectApi.EinsteinPromptTemplateGenerationsInput input =
                new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            input.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
            input.additionalConfig.applicationName = 'PromptTemplateGenerationsInvocable';
            input.isPreview = false;

            Map<String, ConnectApi.WrappedValue> valueMap = new Map<String, ConnectApi.WrappedValue>();
            ConnectApi.WrappedValue lobVal = new ConnectApi.WrappedValue();
            lobVal.value = lob;
            valueMap.put('Input:LineOfBusiness', lobVal);

            ConnectApi.WrappedValue itemsVal = new ConnectApi.WrappedValue();
            itemsVal.value = missingList;
            valueMap.put('Input:MissingItems', itemsVal);

            ConnectApi.WrappedValue insuredVal = new ConnectApi.WrappedValue();
            insuredVal.value = String.isNotBlank(sub.Insured_Name__c) ? sub.Insured_Name__c : 'the insured';
            valueMap.put('Input:InsuredName', insuredVal);

            input.inputParams = valueMap;

            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation response =
                ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(promptName, input);

            return response.generations[0].text;

        } catch (Exception e) {
            // Fall back to a simple rule-based template if Agentforce is unavailable
            return buildFallbackDraft(sub, missingItems, lob);
        }
    }

    private static String buildFallbackDraft(Submission__c sub, List<Missing_Item__c> missingItems, String lob) {
        List<String> lines = new List<String>();
        lines.add('Dear Broker,');
        lines.add('');
        lines.add('Thank you for submitting your ' + lob + ' application for ' +
                  (String.isNotBlank(sub.Insured_Name__c) ? sub.Insured_Name__c : 'your client') + '.');
        lines.add('');
        lines.add('To complete our review, we require the following additional information:');
        lines.add('');
        for (Missing_Item__c item : missingItems) {
            lines.add('  • ' + item.Missing_Message__c);
        }
        lines.add('');
        lines.add('Please provide the above at your earliest convenience so we can proceed with underwriting.');
        lines.add('');
        lines.add('Thank you,');
        lines.add('The Underwriting Team');
        return String.join(lines, '\n');
    }
}
