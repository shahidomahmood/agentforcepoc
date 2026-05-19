global class SubmissionEmailHandler implements Messaging.InboundEmailHandler {

    global Messaging.InboundEmailResult handleInboundEmail(
        Messaging.InboundEmail email,
        Messaging.InboundEnvelope envelope
    ) {
        Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();

        try {
            Submission_Email__c emailRecord = SubmissionEmailService.createFromEmail(email);

            SubmissionFileService.storeAttachments(
                email.binaryAttachments,
                email.textAttachments,
                emailRecord.Id
            );

            result.success = true;

        } catch (Exception e) {
            System.debug('SubmissionEmailHandler error: ' + e.getMessage()
                + '\n' + e.getStackTraceString());
            result.success = false;
            result.message = e.getMessage();
        }

        return result;
    }
}