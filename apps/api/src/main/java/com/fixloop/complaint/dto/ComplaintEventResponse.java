package com.fixloop.complaint.dto;

import java.time.Instant;
import java.util.Map;

public record ComplaintEventResponse(
        long id,
        String actorRole,
        String actorName,
        String eventType,
        String fromStatus,
        String toStatus,
        Map<String, Object> payload,
        Instant createdAt) {
}
