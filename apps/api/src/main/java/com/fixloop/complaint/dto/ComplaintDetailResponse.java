package com.fixloop.complaint.dto;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import com.fasterxml.jackson.annotation.JsonInclude;

@JsonInclude(JsonInclude.Include.NON_NULL)
public record ComplaintDetailResponse(
        UUID id,
        String code,
        String title,
        String description,
        String severity,
        String status,
        UUID categoryId,
        String categoryName,
        String categoryTheme,
        boolean isSensitive,
        String photoPolicy,
        UUID locationId,
        String locationName,
        String locationPath,
        UUID departmentId,
        String departmentName,
        String departmentCode,
        UUID assignedTo,
        String assigneeName,
        Instant slaDueAt,
        int escalationLevel,
        int reopenCount,
        int version,
        boolean isMine,
        ReporterSummary reporter,
        Instant createdAt,
        Instant updatedAt,
        Instant resolvedAt,
        Instant verifiedAt,
        List<ComplaintEventResponse> events,
        List<ComplaintAttachmentResponse> attachments) {
}
