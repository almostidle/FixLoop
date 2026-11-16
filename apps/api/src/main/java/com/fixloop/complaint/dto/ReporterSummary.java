package com.fixloop.complaint.dto;

import java.util.UUID;

public record ReporterSummary(UUID id, String fullName, String email) {
}
