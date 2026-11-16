package com.fixloop.complaint.dto;

import java.util.List;
import java.util.UUID;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

public record CreateComplaintRequest(
        @NotNull(message = "is required")
        UUID categoryId,
        @NotNull(message = "is required")
        UUID locationId,
        @NotBlank(message = "is required")
        @Size(min = 5, max = 120, message = "must be between 5 and 120 characters")
        String title,
        @Size(max = 2000, message = "must be at most 2000 characters")
        String description,
        String severity,
        List<String> attachmentKeys) {
}
