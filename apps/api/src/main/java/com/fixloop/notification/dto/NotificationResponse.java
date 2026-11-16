package com.fixloop.notification.dto;

import java.time.Instant;
import java.util.Map;
import java.util.UUID;

public record NotificationResponse(
        UUID id,
        String type,
        String message,
        UUID complaintId,
        String status,
        Instant createdAt,
        Instant readAt,
        Map<String, Object> payload) {
}
