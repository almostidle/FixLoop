package com.fixloop.directory.dto;

import java.util.UUID;

public record DepartmentResponse(
        UUID id,
        String name,
        String code,
        String kind,
        UUID headUserId) {
}
