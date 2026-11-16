package com.fixloop.complaint;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.stereotype.Service;

/**
 * Config-driven, priority-ordered routing engine (bible 10.2).
 *
 * <p>Sensitive categories are restricted to {@code RESTRICTED} target departments
 * so a broad fallback rule can never accidentally leak a sensitive report into a
 * general service queue.
 */
@Service
public class RoutingService {

    public Optional<RoutingDecision> match(List<RoutingRuleRecord> activeRules,
                                           UUID categoryId,
                                           boolean categoryIsSensitive,
                                           String locationPath,
                                           ComplaintSeverity severity) {
        for (RoutingRuleRecord rule : activeRules) {
            if (!rule.active()) {
                continue;
            }
            if (categoryIsSensitive && !"RESTRICTED".equals(rule.departmentKind())) {
                continue;
            }
            if (rule.categoryId() != null && !rule.categoryId().equals(categoryId)) {
                continue;
            }
            if (rule.locationScopeId() != null
                    && !LocationPathMatcher.matchesScope(locationPath, rule.scopeLocationPath())) {
                continue;
            }
            if (rule.minSeverity() != null && !severity.atLeast(rule.minSeverity())) {
                continue;
            }
            boolean fallback = rule.categoryId() == null;
            return Optional.of(new RoutingDecision(rule, fallback));
        }
        return Optional.empty();
    }

    public record RoutingDecision(RoutingRuleRecord rule, boolean fallback) {
    }
}
