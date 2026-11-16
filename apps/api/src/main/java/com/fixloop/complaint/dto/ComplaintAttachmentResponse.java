package com.fixloop.complaint.dto;

import java.time.Instant;
import java.util.UUID;

public record ComplaintAttachmentResponse(
        UUID id,
        Long eventId,
        String kind,
        String storageKey,
        String mimeType,
        long sizeBytes,
        Instant createdAt) {
}
