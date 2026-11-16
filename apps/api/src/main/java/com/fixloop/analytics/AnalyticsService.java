package com.fixloop.analytics;

import java.util.List;
import java.util.UUID;

import com.fixloop.analytics.dto.AnalyticsSummaryResponse;
import com.fixloop.analytics.dto.AnalyticsSummaryResponse.DailyCreatedCount;
import com.fixloop.analytics.dto.AnalyticsSummaryResponse.DepartmentCount;
import com.fixloop.analytics.dto.AnalyticsSummaryResponse.StatusCount;
import com.fixloop.auth.AuthService;
import com.fixloop.auth.Role;
import com.fixloop.auth.UserAccount;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Role-aware operational analytics summary backed by PostgreSQL views. */
@Service
@Transactional(readOnly = true)
public class AnalyticsService {
    private final AnalyticsRepository repository;
    private final AuthService authService;

    public AnalyticsService(AnalyticsRepository repository, AuthService authService) {
        this.repository = repository;
        this.authService = authService;
    }

    public AnalyticsSummaryResponse summary(UUID callerId) {
        UserAccount caller = authService.requireActiveUser(callerId);
        List<StatusCount> statusCounts = repository.findStatusCounts();

        long total = 0L;
        long open = 0L;
        long inProgress = 0L;
        long awaitingVerification = 0L;
        long verified = 0L;
        long rejected = 0L;

        for (StatusCount row : statusCounts) {
            long c = row.count();
            total += c;
            switch (row.status()) {
                case "REPORTED", "ASSIGNED", "REOPENED" -> open += c;
                case "IN_PROGRESS" -> {
                    open += c;
                    inProgress += c;
                }
                case "RESOLVED" -> awaitingVerification += c;
                case "VERIFIED" -> verified += c;
                case "REJECTED" -> rejected += c;
                default -> {
                    // Ignore unknown statuses safely.
                }
            }
        }

        long overdueCount = repository.countOverdueOpen();

        if (caller.role() == Role.STUDENT) {
            return new AnalyticsSummaryResponse(
                total, open, inProgress, awaitingVerification, verified, rejected,
                overdueCount, statusCounts, List.of(), List.of());
        }

        List<DepartmentCount> departmentCounts = repository.findOpenByDepartment().stream()
            .filter(row -> caller.role() == Role.ADMIN
                || !"RESTRICTED".equals(row.departmentKind())
                || (caller.departmentId() != null && caller.departmentId().equals(row.departmentId())))
            .map(row -> new DepartmentCount(
                row.departmentId(), row.departmentCode(), row.departmentName(), row.openCount()))
            .toList();

        List<DailyCreatedCount> createdPerDay = repository.findCreatedPerDay();

        return new AnalyticsSummaryResponse(
            total, open, inProgress, awaitingVerification, verified, rejected,
            overdueCount, statusCounts, departmentCounts, createdPerDay);
    }
}
