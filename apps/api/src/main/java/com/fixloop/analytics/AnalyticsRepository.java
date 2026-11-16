package com.fixloop.analytics;

import java.sql.Date;
import java.util.List;
import java.util.UUID;

import com.fixloop.analytics.dto.AnalyticsSummaryResponse.DailyCreatedCount;
import com.fixloop.analytics.dto.AnalyticsSummaryResponse.StatusCount;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

/** Queries the analytics database views ({@code v_open_by_status}, {@code v_open_by_department}, {@code v_created_per_day}). */
@Repository
public class AnalyticsRepository {
    private final JdbcTemplate jdbc;

    public AnalyticsRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public List<StatusCount> findStatusCounts() {
        return jdbc.query(
            "SELECT status, total FROM v_open_by_status ORDER BY status ASC",
            (rs, rowNum) -> new StatusCount(rs.getString("status"), rs.getLong("total")));
    }

    public List<DepartmentRow> findOpenByDepartment() {
        return jdbc.query(
            "SELECT d.id AS department_id, d.code AS department_code, v.department AS department_name, "
                + "d.kind AS department_kind, v.total "
                + "FROM v_open_by_department v "
                + "JOIN departments d ON d.name = v.department "
                + "ORDER BY v.total DESC, v.department ASC",
            (rs, rowNum) -> new DepartmentRow(
                rs.getObject("department_id", UUID.class),
                rs.getString("department_code"),
                rs.getString("department_name"),
                rs.getString("department_kind"),
                rs.getLong("total")));
    }

    public List<DailyCreatedCount> findCreatedPerDay() {
        return jdbc.query(
            "SELECT day, total FROM v_created_per_day ORDER BY day ASC",
            (rs, rowNum) -> {
                Date day = rs.getDate("day");
                return new DailyCreatedCount(day == null ? null : day.toLocalDate(), rs.getLong("total"));
            });
    }

    public long countOverdueOpen() {
        Long count = jdbc.queryForObject(
            "SELECT count(*) FROM complaints "
                + "WHERE sla_due_at IS NOT NULL AND sla_due_at < now() "
                + "AND status NOT IN ('RESOLVED', 'VERIFIED', 'REJECTED')",
            Long.class);
        return count == null ? 0L : count;
    }

    public record DepartmentRow(
            UUID departmentId,
            String departmentCode,
            String departmentName,
            String departmentKind,
            long openCount) {
    }
}
