package com.fixloop.analytics.dto;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

public record AnalyticsSummaryResponse(
        long totalComplaints,
        long openCount,
        long inProgressCount,
        long awaitingVerificationCount,
        long verifiedCount,
        long rejectedCount,
        long overdueCount,
        List<StatusCount> byStatus,
        List<DepartmentCount> byDepartment,
        List<DailyCreatedCount> createdPerDay) {

    public record StatusCount(String status, long count) {
    }

    public record DepartmentCount(
            UUID departmentId,
            String departmentCode,
            String departmentName,
            long openCount) {
    }

    public record DailyCreatedCount(LocalDate day, long count) {
    }
}
