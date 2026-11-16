package com.fixloop.complaint;

import java.util.UUID;

public record RoutingRuleRecord(
        UUID id,
        int priority,
        UUID categoryId,
        UUID locationScopeId,
        String scopeLocationPath,
        ComplaintSeverity minSeverity,
        UUID departmentId,
        String departmentCode,
        String departmentName,
        String departmentKind,
        boolean active,
        String note) {
}
