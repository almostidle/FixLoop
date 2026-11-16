package com.fixloop.directory.dto;

import java.util.UUID;

public record CategoryResponse(
        UUID id,
        String name,
        String theme,
        String defaultSeverity,
        String photoPolicy,
        boolean isSensitive,
        int sortOrder) {
}
