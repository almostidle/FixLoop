package com.fixloop.complaint;

import java.util.Locale;

import com.fixloop.common.ApiException;

public enum ComplaintStatus {
    REPORTED,
    ASSIGNED,
    IN_PROGRESS,
    RESOLVED,
    VERIFIED,
    REOPENED,
    REJECTED;

    public boolean isTerminal() {
        return this == VERIFIED || this == REJECTED;
    }

    public boolean isOpenForSla() {
        return this != RESOLVED && this != VERIFIED && this != REJECTED;
    }

    public static ComplaintStatus fromString(String raw) {
        if (raw == null || raw.isBlank()) {
            throw ApiException.badRequest("VALIDATION_FAILED", "A target status is required.");
        }
        try {
            return ComplaintStatus.valueOf(raw.trim().toUpperCase(Locale.ROOT));
        } catch (IllegalArgumentException exception) {
            throw ApiException.badRequest("VALIDATION_FAILED", "Unknown status: " + raw.trim());
        }
    }
}
