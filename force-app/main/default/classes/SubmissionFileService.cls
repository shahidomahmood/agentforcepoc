public without sharing class SubmissionFileService {

    public static void storeAttachments(
        List<Messaging.InboundEmail.BinaryAttachment> binaryAttachments,
        List<Messaging.InboundEmail.TextAttachment>   textAttachments,
        Id parentId
    ) {
        List<ContentVersion> versions = new List<ContentVersion>();

        if (binaryAttachments != null) {
            for (Messaging.InboundEmail.BinaryAttachment att : binaryAttachments) {
                versions.add(new ContentVersion(
                    Title                  = att.filename,
                    PathOnClient           = att.filename,
                    VersionData            = att.body,
                    FirstPublishLocationId = parentId
                ));
            }
        }

        if (textAttachments != null) {
            for (Messaging.InboundEmail.TextAttachment att : textAttachments) {
                versions.add(new ContentVersion(
                    Title                  = att.filename,
                    PathOnClient           = att.filename,
                    VersionData            = Blob.valueOf(att.body),
                    FirstPublishLocationId = parentId
                ));
            }
        }

        if (!versions.isEmpty()) {
            insert versions;
        }
    }
}