package com.fixloop.complaint;

import java.util.Locale;

import com.fixloop.common.ApiException;

public enum ComplaintSeverity {
    LOW(1),
    MEDIUM(2),
    HIGH(3),
    CRITICAL(4);

    private final int rank;

    ComplaintSeverity(int rank) {
        this.rank = rank;
    }

    public int rank() {
        return rank;
    }

    public boolean atLeast(ComplaintSeverity threshold) {
        return threshold == null || this.rank >= threshold.rank;
    }

    public static ComplaintSeverity fromString(String raw) {
        if (raw == null || raw.isBlank()) {
            throw ApiException.badRequest("VALIDATION_FAILED", "Severity is required.");
        }
        try {
            return ComplaintSeverity.valueOf(raw.trim().toUpperCase(Locale.ROOT));
        } catch (IllegalArgumentException exception) {
            throw ApiException.badRequest("VALIDATION_FAILED", "Unknown severity: " + raw.trim());
        }
    }
}
