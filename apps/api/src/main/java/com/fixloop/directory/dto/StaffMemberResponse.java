package com.fixloop.directory.dto;

import java.util.UUID;

import com.fixloop.auth.Role;

public record StaffMemberResponse(
        UUID id,
        String fullName,
        String email,
        Role role,
        UUID departmentId,
        String departmentName,
        UUID scopeLocationId) {
}
