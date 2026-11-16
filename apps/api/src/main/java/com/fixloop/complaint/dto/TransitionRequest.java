package com.fixloop.complaint.dto;

import java.util.List;
import java.util.UUID;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

public record TransitionRequest(
        @NotBlank(message = "is required")
        String toStatus,
        @NotNull(message = "is required")
        Integer version,
        @Size(max = 2000, message = "must be at most 2000 characters")
        String note,
        UUID departmentId,
        UUID assignedTo,
        List<String> attachmentKeys) {
}
