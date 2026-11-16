package com.fixloop.complaint;

import java.util.UUID;

import com.fixloop.auth.Role;
import com.fixloop.auth.UserAccount;
import org.springframework.stereotype.Component;

/**
 * Enforces complaint visibility, sensitive-category isolation, and reporter
 * anonymity (bible 4.3, 4.4, 14.2).
 */
@Component
public class ComplaintAccessPolicy {

    public boolean isSensitive(ComplaintRecord complaint) {
        return complaint.categoryIsSensitive() || "RESTRICTED".equals(complaint.departmentKind());
    }

    public boolean canView(UserAccount caller, ComplaintRecord complaint,
                           String callerScopePath, String callerScopeType) {
        if (caller == null || complaint == null) {
            return false;
        }
        if (caller.role() == Role.ADMIN) {
            return true;
        }
        if (complaint.reporterId().equals(caller.id())) {
            return true;
        }

        if (isSensitive(complaint)) {
            return (caller.role() == Role.STAFF || caller.role() == Role.SUPERVISOR)
                && caller.departmentId() != null
                && caller.departmentId().equals(complaint.departmentId());
        }

        return switch (caller.role()) {
            case ADMIN -> true;
            case STUDENT -> true; // non-sensitive campus issues are visible without reporter identity
            case STAFF -> (caller.departmentId() != null && caller.departmentId().equals(complaint.departmentId()))
                || caller.id().equals(complaint.assignedTo());
            case SUPERVISOR -> canSupervisorAccessNonSensitive(caller, complaint, callerScopePath, callerScopeType);
        };
    }

    public boolean canSeeReporterIdentity(UserAccount caller, ComplaintRecord complaint) {
        return caller.role() == Role.ADMIN || complaint.reporterId().equals(caller.id());
    }

    public boolean canPostNote(UserAccount caller, ComplaintRecord complaint,
                               String callerScopePath, String callerScopeType) {
        if (!canView(caller, complaint, callerScopePath, callerScopeType)) {
            return false;
        }
        if (caller.role() == Role.STUDENT) {
            return complaint.reporterId().equals(caller.id());
        }
        return caller.role() == Role.STAFF
            || caller.role() == Role.SUPERVISOR
            || caller.role() == Role.ADMIN;
    }

    public boolean canSeeActorIdentity(UserAccount caller, UUID actorId, String actorRole) {
        if (caller.role() == Role.ADMIN) {
            return true;
        }
        if (actorId != null && actorId.equals(caller.id())) {
            return true;
        }
        return !"STUDENT".equals(actorRole);
    }

    private static boolean canSupervisorAccessNonSensitive(UserAccount caller, ComplaintRecord complaint,
                                                           String callerScopePath, String callerScopeType) {
        if (caller.departmentId() != null && caller.departmentId().equals(complaint.departmentId())) {
            return true;
        }
        if (caller.id().equals(complaint.assignedTo())) {
            return true;
        }
        // Unrouted non-sensitive complaints are visible to supervisors within their location scope.
        if (complaint.departmentId() == null) {
            return caller.scopeLocationId() == null
                || (callerScopePath != null && LocationPathMatcher.matchesScope(complaint.locationPath(), callerScopePath));
        }
        if (caller.scopeLocationId() != null && callerScopePath != null) {
            boolean campusWideDepartmentHead = caller.departmentId() != null && "CAMPUS".equals(callerScopeType);
            if (!campusWideDepartmentHead) {
                return LocationPathMatcher.matchesScope(complaint.locationPath(), callerScopePath);
            }
        }
        return false;
    }
}
