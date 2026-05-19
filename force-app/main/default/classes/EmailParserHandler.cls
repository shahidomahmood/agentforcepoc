global class EmailParserHandler implements Messaging.InboundEmailHandler {

    global Messaging.InboundEmailResult handleInboundEmail(
        Messaging.InboundEmail email,
        Messaging.InboundEnvelope envelope
    ) {
        Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();

        try {
            // ── ATTACHMENT COUNT ─────────────────────────────
            Integer attachmentCount = 0;
            if (email.binaryAttachments != null) {
                attachmentCount += email.binaryAttachments.size();
            }
            if (email.textAttachments != null) {
                attachmentCount += email.textAttachments.size();
            }

            // ── BODY (prefer plain text, fall back to HTML) ──
            String body = String.isNotBlank(email.plainTextBody)
                ? email.plainTextBody
                : email.htmlBody;

            // ── CREATE Submission_Email__c RECORD ────────────
            Submission_Email__c emailRecord = new Submission_Email__c(
                From_Email__c      = email.fromAddress,
                From_Name__c       = email.fromName,
                Subject__c         = email.subject,
                Body__c            = body,
                Received_Date__c   = DateTime.now(),
                Status__c          = 'Received',
                Attachment_Count__c = attachmentCount
            );
            insert emailRecord;

            System.debug('Submission_Email__c created: ' + emailRecord.Id);

            // ── LOG PDF ATTACHMENTS FOR FUTURE PROCESSING ───
            if (email.binaryAttachments != null) {
                for (Messaging.InboundEmail.BinaryAttachment att : email.binaryAttachments) {
                    System.debug('Attachment: ' + att.filename
                        + ' (' + att.mimeTypeSubType + ', '
                        + att.body.size() + ' bytes)');
                }
            }

            result.success = true;

        } catch (Exception e) {
            System.debug('EmailParserHandler error: ' + e.getMessage()
                + '\n' + e.getStackTraceString());
            result.success    = false;
            result.message    = e.getMessage();
        }

        return result;
    }
}