package com.fixloop.complaint;

import java.time.Instant;
import java.util.UUID;

/** Internal projection of a complaint joined with its reference tables. */
public record ComplaintRecord(
        UUID id,
        String code,
        UUID reporterId,
        String reporterName,
        String reporterEmail,
        UUID categoryId,
        String categoryName,
        String categoryTheme,
        boolean categoryIsSensitive,
        String categoryPhotoPolicy,
        UUID locationId,
        String locationName,
        String locationPath,
        String title,
        String description,
        String severity,
        String status,
        UUID departmentId,
        String departmentName,
        String departmentCode,
        String departmentKind,
        UUID departmentHeadUserId,
        UUID assignedTo,
        String assigneeName,
        Instant slaDueAt,
        int escalationLevel,
        int reopenCount,
        int version,
        String idempotencyKey,
        Instant createdAt,
        Instant updatedAt,
        Instant resolvedAt,
        Instant verifiedAt) {
}
