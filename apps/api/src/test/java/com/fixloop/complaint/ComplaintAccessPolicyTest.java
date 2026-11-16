package com.fixloop.complaint;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Instant;
import java.util.UUID;

import com.fixloop.auth.Role;
import com.fixloop.auth.UserAccount;
import org.junit.jupiter.api.Test;

class ComplaintAccessPolicyTest {
    private final ComplaintAccessPolicy policy = new ComplaintAccessPolicy();

    private static final UUID STUDENT_1 = UUID.randomUUID();
    private static final UUID STUDENT_2 = UUID.randomUUID();
    private static final UUID DEPT_FAC = UUID.randomUUID();
    private static final UUID DEPT_IT = UUID.randomUUID();
    private static final UUID DEPT_ICC = UUID.randomUUID();
    private static final UUID LOC_CAMPUS = UUID.randomUUID();
    private static final UUID LOC_HOSTEL = UUID.randomUUID();

    @Test
    void hidesSensitiveComplaintsFromEveryoneExceptReporterAdminAndAssignedDepartment() {
        ComplaintRecord sensitive = sampleComplaint(STUDENT_1, DEPT_ICC, "RESTRICTED", true, "/bmu/academic");

        assertThat(policy.canView(user(STUDENT_1, Role.STUDENT, null, null), sensitive, null, null)).isTrue();
        assertThat(policy.canView(user(STUDENT_2, Role.STUDENT, null, null), sensitive, null, null)).isFalse();
        assertThat(policy.canView(user(UUID.randomUUID(), Role.STAFF, DEPT_FAC, null), sensitive, null, null)).isFalse();
        assertThat(policy.canView(user(UUID.randomUUID(), Role.SUPERVISOR, DEPT_FAC, LOC_CAMPUS), sensitive, "/bmu", "CAMPUS")).isFalse();
        assertThat(policy.canView(user(UUID.randomUUID(), Role.STAFF, DEPT_ICC, null), sensitive, null, null)).isTrue();
        assertThat(policy.canView(user(UUID.randomUUID(), Role.SUPERVISOR, DEPT_ICC, LOC_CAMPUS), sensitive, "/bmu", "CAMPUS")).isTrue();
        assertThat(policy.canView(user(UUID.randomUUID(), Role.ADMIN, null, null), sensitive, null, null)).isTrue();
    }

    @Test
    void hidesStudentIdentityFromNonAdminPeersAndDepartmentStaff() {
        ComplaintRecord publicIssue = sampleComplaint(STUDENT_1, DEPT_FAC, "SERVICE", false, "/bmu/boys-hostel-t1/room-204");

        UserAccount otherStudent = user(STUDENT_2, Role.STUDENT, null, null);
        UserAccount staff = user(UUID.randomUUID(), Role.STAFF, DEPT_FAC, null);
        UserAccount admin = user(UUID.randomUUID(), Role.ADMIN, null, null);

        assertThat(policy.canSeeReporterIdentity(otherStudent, publicIssue)).isFalse();
        assertThat(policy.canSeeReporterIdentity(staff, publicIssue)).isFalse();
        assertThat(policy.canSeeReporterIdentity(user(STUDENT_1, Role.STUDENT, null, null), publicIssue)).isTrue();
        assertThat(policy.canSeeReporterIdentity(admin, publicIssue)).isTrue();

        assertThat(policy.canPostNote(otherStudent, publicIssue, null, null)).isFalse();
        assertThat(policy.canPostNote(staff, publicIssue, null, null)).isTrue();
    }

    @Test
    void campusWideDepartmentHeadsOnlySeeTheirOwnDepartmentOnceRouted() {
        ComplaintRecord itIssue = sampleComplaint(STUDENT_1, DEPT_IT, "SERVICE", false, "/bmu/academic/lab-3");
        ComplaintRecord unrouted = sampleComplaint(STUDENT_1, null, null, false, "/bmu/academic/lab-3");

        UserAccount facHead = user(UUID.randomUUID(), Role.SUPERVISOR, DEPT_FAC, LOC_CAMPUS);
        UserAccount hostelWarden = user(UUID.randomUUID(), Role.SUPERVISOR, DEPT_FAC, LOC_HOSTEL);

        assertThat(policy.canView(facHead, itIssue, "/bmu", "CAMPUS")).isFalse();
        assertThat(policy.canView(facHead, unrouted, "/bmu", "CAMPUS")).isTrue();
        assertThat(policy.canView(hostelWarden, itIssue, "/bmu/boys-hostel-t1", "BLOCK")).isFalse();
    }

    private static UserAccount user(UUID id, Role role, UUID deptId, UUID scopeLocId) {
        return new UserAccount(id, role.name().toLowerCase() + "@bmu.edu.in", "hash",
            role.name(), role, deptId, scopeLocId, true, false, true);
    }

    private static ComplaintRecord sampleComplaint(UUID reporterId, UUID deptId, String deptKind,
                                                   boolean sensitive, String locationPath) {
        return new ComplaintRecord(
            UUID.randomUUID(), "FL-2026-000099", reporterId, "Student One", "s1@bmu.edu.in",
            UUID.randomUUID(), "Category", "OTHER", sensitive, "OPTIONAL",
            UUID.randomUUID(), "Location", locationPath, "Sample title", "Details", "MEDIUM",
            deptId == null ? "REPORTED" : "ASSIGNED",
            deptId, deptId == null ? null : "Department", deptId == null ? null : "CODE", deptKind,
            null, null, null, Instant.now().plusSeconds(3600), 0, 0, 0, null,
            Instant.now(), Instant.now(), null, null);
    }
}
