global class EmailParserHandler implements Messaging.InboundEmailHandler {
    
    global Messaging.InboundEmailResult handleInboundEmail(
        Messaging.InboundEmail email, 
        Messaging.InboundEnvelope envelope
    ) {
        Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();
        
        try {
            // ── WHO IS IT FROM ──────────────────────────────
            String senderEmail = email.fromAddress;
            String senderName  = email.fromName;
            System.debug('From Email: ' + senderEmail);
            System.debug('From Name: '  + senderName);
            
            // ── SUBJECT ─────────────────────────────────────
            String subject = email.subject;
            System.debug('Subject: ' + subject);
            
            // ── EMAIL BODY ──────────────────────────────────
            String body = email.plainTextBody;
            System.debug('Body: ' + body);
            
            // ── ATTACHMENTS ─────────────────────────────────
            if (email.binaryAttachments != null && 
                email.binaryAttachments.size() > 0) {
                    
                System.debug('Number of Attachments: ' + 
                    email.binaryAttachments.size());
                    
                for (Messaging.InboundEmail.BinaryAttachment att : 
                    email.binaryAttachments) {
                        
                    System.debug('Attachment Name: ' + att.filename);
                    System.debug('Attachment Type: ' + att.mimeTypeSubType);
                    System.debug('Attachment Size (bytes): ' + att.body.size());
                    
                    // If it's a PDF, you can pass att.body to PDF.co here
                    if (att.filename.endsWith('.pdf')) {
                        System.debug('PDF attachment detected: ' + att.filename);
                        // TODO: Call your PDF.co Apex class here
                    }
                }
            } else {
                System.debug('No attachments found.');
            }
            
            // ── LOG TO A SALESFORCE RECORD ───────────────────
            // Optional: find a matching Contact by sender email
            List<Contact> matchingContacts = [
                SELECT Id, Name 
                FROM Contact 
                WHERE Email = :senderEmail 
                LIMIT 1
            ];
            
            if (!matchingContacts.isEmpty()) {
                System.debug('Matched Contact: ' + matchingContacts[0].Name);
                // TODO: Create a Task or update a record here
            } else {
                System.debug('No matching Contact found for: ' + senderEmail);
            }
            
            result.success = true;
            
        } catch (Exception e) {
            System.debug('Error: ' + e.getMessage());
            result.success = false;
        }
        
        return result;
    }
}