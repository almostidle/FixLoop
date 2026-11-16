package com.fixloop.directory.dto;

import java.util.UUID;

public record LocationResponse(
        UUID id,
        UUID parentId,
        String type,
        String name,
        String path) {
}
