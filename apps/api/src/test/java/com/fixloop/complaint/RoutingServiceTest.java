package com.fixloop.complaint;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.Test;

class RoutingServiceTest {
    private final RoutingService routing = new RoutingService();

    private static final UUID CAT_PLUMBING = UUID.randomUUID();
    private static final UUID CAT_SENSITIVE = UUID.randomUUID();
    private static final UUID LOC_HOSTEL = UUID.randomUUID();
    private static final UUID DEPT_FAC = UUID.randomUUID();
    private static final UUID DEPT_HST = UUID.randomUUID();
    private static final UUID DEPT_ICC = UUID.randomUUID();

    @Test
    void matchesHighestPriorityRuleMatchingLocationSubtreeAndSeverity() {
        List<RoutingRuleRecord> rules = List.of(
            new RoutingRuleRecord(UUID.randomUUID(), 5, null, LOC_HOSTEL, "/bmu/boys-hostel-t1",
                ComplaintSeverity.CRITICAL, DEPT_FAC, "FAC", "Facilities", "SERVICE", true, "critical"),
            new RoutingRuleRecord(UUID.randomUUID(), 10, CAT_PLUMBING, LOC_HOSTEL, "/bmu/boys-hostel-t1",
                null, DEPT_HST, "HST", "Hostel", "SERVICE", true, "hostel plumbing"),
            new RoutingRuleRecord(UUID.randomUUID(), 999, null, null, null,
                null, DEPT_FAC, "FAC", "Facilities", "SERVICE", true, "fallback")
        );

        Optional<RoutingService.RoutingDecision> criticalDecision = routing.match(
            rules, CAT_PLUMBING, false, "/bmu/boys-hostel-t1/room-204", ComplaintSeverity.CRITICAL);
        assertThat(criticalDecision).isPresent();
        assertThat(criticalDecision.get().rule().departmentCode()).isEqualTo("FAC");
        assertThat(criticalDecision.get().fallback()).isTrue();

        Optional<RoutingService.RoutingDecision> mediumDecision = routing.match(
            rules, CAT_PLUMBING, false, "/bmu/boys-hostel-t1/room-204", ComplaintSeverity.MEDIUM);
        assertThat(mediumDecision).isPresent();
        assertThat(mediumDecision.get().rule().departmentCode()).isEqualTo("HST");
        assertThat(mediumDecision.get().fallback()).isFalse();
    }

    @Test
    void neverRoutesSensitiveComplaintsIntoNonRestrictedFallbackDepartments() {
        List<RoutingRuleRecord> rulesWithOnlyFallback = List.of(
            new RoutingRuleRecord(UUID.randomUUID(), 999, null, null, null,
                null, DEPT_FAC, "FAC", "Facilities", "SERVICE", true, "fallback")
        );
        assertThat(routing.match(rulesWithOnlyFallback, CAT_SENSITIVE, true, "/bmu", ComplaintSeverity.HIGH))
            .isEmpty();

        List<RoutingRuleRecord> rulesWithIcc = List.of(
            new RoutingRuleRecord(UUID.randomUUID(), 1, CAT_SENSITIVE, null, null,
                null, DEPT_ICC, "ICC", "ICC", "RESTRICTED", true, "icc"),
            new RoutingRuleRecord(UUID.randomUUID(), 999, null, null, null,
                null, DEPT_FAC, "FAC", "Facilities", "SERVICE", true, "fallback")
        );
        Optional<RoutingService.RoutingDecision> decision =
            routing.match(rulesWithIcc, CAT_SENSITIVE, true, "/bmu", ComplaintSeverity.HIGH);
        assertThat(decision).isPresent();
        assertThat(decision.get().rule().departmentCode()).isEqualTo("ICC");
    }
}
