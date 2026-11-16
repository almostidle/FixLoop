package com.fixloop.complaint;

import java.sql.Array;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fixloop.auth.Role;
import com.fixloop.auth.UserAccount;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

/** Plain-SQL persistence for complaints, routing rules, SLA policies, transitions and audit events. */
@Repository
public class ComplaintRepository {
    private static final TypeReference<Map<String, Object>> MAP_TYPE = new TypeReference<>() {};

    private static final String BASE_SELECT = """
        SELECT c.id, c.code, c.reporter_id, rep.full_name AS reporter_name, rep.email AS reporter_email,
               c.category_id, cat.name AS category_name, cat.theme AS category_theme,
               cat.is_sensitive AS category_is_sensitive, cat.photo_policy AS category_photo_policy,
               c.location_id, loc.name AS location_name, loc.path AS location_path,
               c.title, c.description, c.severity, c.status,
               c.department_id, d.name AS department_name, d.code AS department_code,
               d.kind AS department_kind, d.head_user_id AS department_head_user_id,
               c.assigned_to, asg.full_name AS assignee_name,
               c.sla_due_at, c.escalation_level, c.reopen_count, c.version,
               c.idempotency_key, c.created_at, c.updated_at, c.resolved_at, c.verified_at
        FROM complaints c
        JOIN users rep ON rep.id = c.reporter_id
        JOIN categories cat ON cat.id = c.category_id
        JOIN locations loc ON loc.id = c.location_id
        LEFT JOIN departments d ON d.id = c.department_id
        LEFT JOIN users asg ON asg.id = c.assigned_to
        """;

    private static final RowMapper<ComplaintRecord> COMPLAINT_MAPPER = ComplaintRepository::mapComplaint;

    private final JdbcTemplate jdbc;
    private final ObjectMapper objectMapper;

    public ComplaintRepository(JdbcTemplate jdbc, ObjectMapper objectMapper) {
        this.jdbc = jdbc;
        this.objectMapper = objectMapper;
    }

    public String nextComplaintCode() {
        return jdbc.queryForObject(
            "SELECT 'FL-' || EXTRACT(YEAR FROM now())::int || '-' "
                + "|| lpad(nextval('complaint_code_seq')::text, 6, '0')",
            String.class);
    }

    public Optional<ComplaintRecord> findById(UUID id) {
        List<ComplaintRecord> rows = jdbc.query(
            BASE_SELECT + " WHERE c.id = ?", COMPLAINT_MAPPER, id);
        return rows.stream().findFirst();
    }

    public Optional<ComplaintRecord> findByReporterAndIdempotencyKey(UUID reporterId, String idempotencyKey) {
        List<ComplaintRecord> rows = jdbc.query(
            BASE_SELECT + " WHERE c.reporter_id = ? AND c.idempotency_key = ?",
            COMPLAINT_MAPPER, reporterId, idempotencyKey);
        return rows.stream().findFirst();
    }

    public PagedResult findPaged(UserAccount caller, String callerScopePath, String callerScopeType,
                                 ComplaintFilter filter, int page, int size) {
        StringBuilder where = new StringBuilder(" WHERE 1=1");
        List<Object> params = new ArrayList<>();

        // Critical sensitivity guard: restricted complaints are only visible to reporter, ADMIN,
        // or STAFF/SUPERVISOR in the complaint's assigned department.
        if (caller.role() != Role.ADMIN) {
            where.append(" AND ((cat.is_sensitive = false AND (d.id IS NULL OR d.kind <> 'RESTRICTED')) OR c.reporter_id = ?");
            params.add(caller.id());
            if ((caller.role() == Role.STAFF || caller.role() == Role.SUPERVISOR)
                    && caller.departmentId() != null) {
                where.append(" OR c.department_id = ?");
                params.add(caller.departmentId());
            }
            where.append(")");
        }

        // Role-based feed/queue visibility when not restricted to mine=true.
        if (Boolean.TRUE.equals(filter.mine())) {
            where.append(" AND c.reporter_id = ?");
            params.add(caller.id());
        } else {
            appendRoleScope(caller, callerScopePath, callerScopeType, where, params);
        }

        if (Boolean.TRUE.equals(filter.assignedToMe())) {
            where.append(" AND c.assigned_to = ?");
            params.add(caller.id());
        }
        if (Boolean.TRUE.equals(filter.unclaimed())) {
            where.append(" AND c.assigned_to IS NULL AND c.status IN ('ASSIGNED', 'REOPENED')");
        }
        if (Boolean.TRUE.equals(filter.overdue())) {
            where.append(" AND c.sla_due_at IS NOT NULL AND c.sla_due_at < now() "
                + "AND c.status NOT IN ('RESOLVED', 'VERIFIED', 'REJECTED')");
        }
        if (filter.statuses() != null && !filter.statuses().isEmpty()) {
            where.append(" AND c.status IN (");
            for (int i = 0; i < filter.statuses().size(); i++) {
                if (i > 0) {
                    where.append(", ");
                }
                where.append("?");
                params.add(filter.statuses().get(i).name());
            }
            where.append(")");
        }
        if (filter.departmentId() != null) {
            where.append(" AND c.department_id = ?");
            params.add(filter.departmentId());
        }
        if (filter.q() != null && !filter.q().isBlank()) {
            String escaped = "%" + escapeLike(filter.q().trim()) + "%";
            where.append(" AND (c.code ILIKE ? ESCAPE '\\' "
                + "OR c.title ILIKE ? ESCAPE '\\' "
                + "OR coalesce(c.description, '') ILIKE ? ESCAPE '\\' "
                + "OR loc.name ILIKE ? ESCAPE '\\' "
                + "OR cat.name ILIKE ? ESCAPE '\\')");
            for (int i = 0; i < 5; i++) {
                params.add(escaped);
            }
        }

        String fromAndJoins = """
            FROM complaints c
            JOIN users rep ON rep.id = c.reporter_id
            JOIN categories cat ON cat.id = c.category_id
            JOIN locations loc ON loc.id = c.location_id
            LEFT JOIN departments d ON d.id = c.department_id
            LEFT JOIN users asg ON asg.id = c.assigned_to
            """;

        Long total = jdbc.queryForObject(
            "SELECT count(*) " + fromAndJoins + where,
            Long.class, params.toArray());
        long totalElements = total == null ? 0L : total;

        String orderBy = "priority".equalsIgnoreCase(filter.sort())
            ? " ORDER BY CASE c.severity WHEN 'CRITICAL' THEN 1 WHEN 'HIGH' THEN 2 WHEN 'MEDIUM' THEN 3 ELSE 4 END ASC, c.created_at ASC"
            : " ORDER BY c.created_at DESC, c.code DESC";

        List<Object> pageParams = new ArrayList<>(params);
        pageParams.add(size);
        pageParams.add((long) page * size);

        List<ComplaintRecord> items = jdbc.query(
            BASE_SELECT + where + orderBy + " LIMIT ? OFFSET ?",
            COMPLAINT_MAPPER, pageParams.toArray());
        return new PagedResult(items, totalElements);
    }

    public Map<String, Long> countSimilarOpenByStatus(UUID locationId, UUID categoryId) {
        Map<String, Long> counts = new LinkedHashMap<>();
        jdbc.query(
            "SELECT c.status, count(*) AS total "
                + "FROM complaints c "
                + "JOIN categories cat ON cat.id = c.category_id "
                + "LEFT JOIN departments d ON d.id = c.department_id "
                + "WHERE c.location_id = ? AND c.category_id = ? "
                + "AND c.status NOT IN ('RESOLVED', 'VERIFIED', 'REJECTED') "
                + "AND cat.is_sensitive = false "
                + "AND (d.id IS NULL OR d.kind <> 'RESTRICTED') "
                + "GROUP BY c.status ORDER BY total DESC, c.status ASC",
            rs -> {
                counts.put(rs.getString("status"), rs.getLong("total"));
            },
            locationId, categoryId);
        return counts;
    }

    public UUID insertComplaint(String code, UUID reporterId, UUID categoryId, UUID locationId,
                                String title, String description, String severity, String idempotencyKey) {
        return jdbc.queryForObject(
            "INSERT INTO complaints (code, reporter_id, category_id, location_id, title, description, "
                + "severity, status, idempotency_key) "
                + "VALUES (?, ?, ?, ?, ?, ?, ?, 'REPORTED', ?) RETURNING id",
            UUID.class, code, reporterId, categoryId, locationId, title, description, severity, idempotencyKey);
    }

    public Long insertEvent(UUID complaintId, UUID actorId, String actorRole, String eventType,
                            String fromStatus, String toStatus, Map<String, Object> payload) {
        String json = toJson(payload);
        return jdbc.queryForObject(
            "INSERT INTO complaint_events (complaint_id, actor_id, actor_role, event_type, from_status, to_status, payload) "
                + "VALUES (?, ?, ?, ?, ?, ?, ?::jsonb) RETURNING id",
            Long.class, complaintId, actorId, actorRole, eventType, fromStatus, toStatus, json);
    }

    public void updateInitialRoutingAndSla(UUID complaintId, String status, UUID departmentId,
                                           Instant slaDueAt, boolean routed) {
        Timestamp dueTs = slaDueAt == null ? null : Timestamp.from(slaDueAt);
        if (routed) {
            jdbc.update(
                "UPDATE complaints SET status = ?, department_id = ?, sla_due_at = ?, "
                    + "version = version + 1, updated_at = now() WHERE id = ?",
                status, departmentId, dueTs, complaintId);
        } else {
            jdbc.update(
                "UPDATE complaints SET sla_due_at = ? WHERE id = ?",
                dueTs, complaintId);
        }
    }

    public int applyClaim(UUID complaintId, int expectedVersion, UUID assigneeId) {
        return jdbc.update(
            "UPDATE complaints SET status = 'IN_PROGRESS', assigned_to = ?, "
                + "version = version + 1, updated_at = now() "
                + "WHERE id = ? AND version = ? AND status = 'ASSIGNED' "
                + "AND (assigned_to IS NULL OR assigned_to = ?)",
            assigneeId, complaintId, expectedVersion, assigneeId);
    }

    public int applyRelease(UUID complaintId, int expectedVersion) {
        return jdbc.update(
            "UPDATE complaints SET status = 'ASSIGNED', assigned_to = NULL, "
                + "version = version + 1, updated_at = now() "
                + "WHERE id = ? AND version = ? AND status = 'IN_PROGRESS'",
            complaintId, expectedVersion);
    }

    public int applyResolve(UUID complaintId, int expectedVersion) {
        return jdbc.update(
            "UPDATE complaints SET status = 'RESOLVED', resolved_at = now(), "
                + "version = version + 1, updated_at = now() "
                + "WHERE id = ? AND version = ? AND status = 'IN_PROGRESS'",
            complaintId, expectedVersion);
    }

    public int applyVerify(UUID complaintId, int expectedVersion) {
        return jdbc.update(
            "UPDATE complaints SET status = 'VERIFIED', verified_at = now(), "
                + "version = version + 1, updated_at = now() "
                + "WHERE id = ? AND version = ? AND status = 'RESOLVED'",
            complaintId, expectedVersion);
    }

    public int applyReopen(UUID complaintId, int expectedVersion) {
        return jdbc.update(
            "UPDATE complaints SET status = 'REOPENED', reopen_count = reopen_count + 1, "
                + "resolved_at = NULL, version = version + 1, updated_at = now() "
                + "WHERE id = ? AND version = ? AND status = 'RESOLVED'",
            complaintId, expectedVersion);
    }

    public int applySystemRouteFromReopened(UUID complaintId, UUID departmentId, Instant slaDueAt) {
        Timestamp dueTs = slaDueAt == null ? null : Timestamp.from(slaDueAt);
        return jdbc.update(
            "UPDATE complaints SET status = 'ASSIGNED', department_id = ?, assigned_to = NULL, "
                + "sla_due_at = COALESCE(?, sla_due_at), version = version + 1, updated_at = now() "
                + "WHERE id = ? AND status = 'REOPENED'",
            departmentId, dueTs, complaintId);
    }

    public int applyRouteFromReported(UUID complaintId, int expectedVersion, UUID departmentId,
                                      UUID assignedTo, Instant slaDueAt) {
        Timestamp dueTs = slaDueAt == null ? null : Timestamp.from(slaDueAt);
        return jdbc.update(
            "UPDATE complaints SET status = 'ASSIGNED', department_id = ?, assigned_to = ?, "
                + "sla_due_at = COALESCE(sla_due_at, ?), version = version + 1, updated_at = now() "
                + "WHERE id = ? AND version = ? AND status = 'REPORTED'",
            departmentId, assignedTo, dueTs, complaintId, expectedVersion);
    }

    public int applyReassign(UUID complaintId, int expectedVersion, UUID departmentId, UUID assignedTo) {
        return jdbc.update(
            "UPDATE complaints SET status = 'ASSIGNED', department_id = ?, assigned_to = ?, "
                + "version = version + 1, updated_at = now() "
                + "WHERE id = ? AND version = ? AND status = 'ASSIGNED'",
            departmentId, assignedTo, complaintId, expectedVersion);
    }

    public int applyReject(UUID complaintId, int expectedVersion) {
        return jdbc.update(
            "UPDATE complaints SET status = 'REJECTED', version = version + 1, updated_at = now() "
                + "WHERE id = ? AND version = ? AND status = 'REPORTED'",
            complaintId, expectedVersion);
    }

    public void touchUpdatedAt(UUID complaintId) {
        jdbc.update("UPDATE complaints SET updated_at = now() WHERE id = ?", complaintId);
    }

    public List<ComplaintEventRecord> findEventsForComplaint(UUID complaintId) {
        return jdbc.query(
            "SELECT e.id, e.complaint_id, e.actor_id, e.actor_role, u.full_name AS actor_name, "
                + "e.event_type, e.from_status, e.to_status, e.payload::text AS payload_text, e.created_at "
                + "FROM complaint_events e "
                + "LEFT JOIN users u ON u.id = e.actor_id "
                + "WHERE e.complaint_id = ? "
                + "ORDER BY e.created_at ASC, e.id ASC",
            (rs, rowNum) -> {
                OffsetDateTime created = rs.getObject("created_at", OffsetDateTime.class);
                return new ComplaintEventRecord(
                    rs.getLong("id"),
                    rs.getObject("complaint_id", UUID.class),
                    rs.getObject("actor_id", UUID.class),
                    rs.getString("actor_role"),
                    rs.getString("actor_name"),
                    rs.getString("event_type"),
                    rs.getString("from_status"),
                    rs.getString("to_status"),
                    parseJson(rs.getString("payload_text")),
                    created == null ? Instant.now() : created.toInstant());
            },
            complaintId);
    }

    public List<RoutingRuleRecord> findActiveRoutingRules() {
        return jdbc.query(
            "SELECT r.id, r.priority, r.category_id, r.location_scope_id, l.path AS scope_path, "
                + "r.min_severity, r.department_id, d.code AS dept_code, d.name AS dept_name, "
                + "d.kind AS dept_kind, r.active, r.note "
                + "FROM routing_rules r "
                + "JOIN departments d ON d.id = r.department_id "
                + "LEFT JOIN locations l ON l.id = r.location_scope_id "
                + "WHERE r.active = true AND d.active = true "
                + "ORDER BY r.priority ASC, r.id ASC",
            (rs, rowNum) -> {
                String minSev = rs.getString("min_severity");
                return new RoutingRuleRecord(
                    rs.getObject("id", UUID.class),
                    rs.getInt("priority"),
                    rs.getObject("category_id", UUID.class),
                    rs.getObject("location_scope_id", UUID.class),
                    rs.getString("scope_path"),
                    minSev == null ? null : ComplaintSeverity.valueOf(minSev),
                    rs.getObject("department_id", UUID.class),
                    rs.getString("dept_code"),
                    rs.getString("dept_name"),
                    rs.getString("dept_kind"),
                    rs.getBoolean("active"),
                    rs.getString("note"));
            });
    }

    public Optional<Integer> findResolveMinutes(UUID categoryId, String severity) {
        List<Integer> rows = jdbc.query(
            "SELECT resolve_minutes FROM sla_policies "
                + "WHERE severity = ? AND (category_id = ? OR category_id IS NULL) "
                + "ORDER BY category_id NULLS LAST LIMIT 1",
            (rs, rowNum) -> rs.getInt("resolve_minutes"),
            severity, categoryId);
        return rows.stream().findFirst();
    }

    public Optional<TransitionRuleRecord> findTransitionRule(String fromStatus, String toStatus) {
        String sql = fromStatus == null
            ? "SELECT from_status, to_status, allowed_roles, requires_note, system_only "
                + "FROM status_transitions WHERE from_status IS NULL AND to_status = ?"
            : "SELECT from_status, to_status, allowed_roles, requires_note, system_only "
                + "FROM status_transitions WHERE from_status = ? AND to_status = ?";
        Object[] args = fromStatus == null ? new Object[] {toStatus} : new Object[] {fromStatus, toStatus};
        List<TransitionRuleRecord> rows = jdbc.query(sql, (rs, rowNum) -> {
            Array sqlArray = rs.getArray("allowed_roles");
            List<String> roles = List.of();
            if (sqlArray != null) {
                Object array = sqlArray.getArray();
                if (array instanceof String[] strings) {
                    roles = List.of(strings);
                }
            }
            return new TransitionRuleRecord(
                rs.getString("from_status"),
                rs.getString("to_status"),
                roles,
                rs.getBoolean("requires_note"),
                rs.getBoolean("system_only"));
        }, args);
        return rows.stream().findFirst();
    }

    private static void appendRoleScope(UserAccount caller, String callerScopePath, String callerScopeType,
                                        StringBuilder where, List<Object> params) {
        switch (caller.role()) {
            case ADMIN, STUDENT -> {
                // ADMIN sees all; STUDENT sees own + non-sensitive campus feed (enforced by sensitivity guard above).
            }
            case STAFF -> {
                if (caller.departmentId() != null) {
                    where.append(" AND (c.department_id = ? OR c.assigned_to = ? OR c.reporter_id = ?)");
                    params.add(caller.departmentId());
                    params.add(caller.id());
                    params.add(caller.id());
                } else {
                    where.append(" AND (c.assigned_to = ? OR c.reporter_id = ?)");
                    params.add(caller.id());
                    params.add(caller.id());
                }
            }
            case SUPERVISOR -> {
                boolean hasDept = caller.departmentId() != null;
                boolean hasLocationPath = callerScopePath != null && !callerScopePath.isBlank();
                boolean hasNonCampusScope = hasLocationPath && !(hasDept && "CAMPUS".equals(callerScopeType));
                where.append(" AND (c.assigned_to = ? OR c.reporter_id = ?");
                params.add(caller.id());
                params.add(caller.id());
                if (hasDept) {
                    where.append(" OR c.department_id = ?");
                    params.add(caller.departmentId());
                }
                if (hasNonCampusScope) {
                    String normalized = LocationPathMatcher.normalize(callerScopePath);
                    String prefix = "/".equals(normalized) ? "/" : normalized + "/";
                    where.append(" OR rtrim(loc.path, '/') = ? OR starts_with(loc.path, ?)");
                    params.add(normalized);
                    params.add(prefix);
                } else if (hasLocationPath) {
                    // Campus-wide department heads can also see unrouted complaints for triage.
                    String normalized = LocationPathMatcher.normalize(callerScopePath);
                    String prefix = "/".equals(normalized) ? "/" : normalized + "/";
                    where.append(" OR (c.department_id IS NULL AND (rtrim(loc.path, '/') = ? OR starts_with(loc.path, ?)))");
                    params.add(normalized);
                    params.add(prefix);
                } else if (caller.scopeLocationId() == null) {
                    where.append(" OR c.department_id IS NULL");
                }
                where.append(")");
            }
        }
    }

    private static String escapeLike(String value) {
        return value
            .replace("\\", "\\\\")
            .replace("%", "\\%")
            .replace("_", "\\_");
    }

    private String toJson(Map<String, Object> payload) {
        try {
            return objectMapper.writeValueAsString(payload == null ? Map.of() : payload);
        } catch (JsonProcessingException exception) {
            throw new IllegalStateException("Could not serialize event payload", exception);
        }
    }

    private Map<String, Object> parseJson(String raw) {
        if (raw == null || raw.isBlank()) {
            return Map.of();
        }
        try {
            return Collections.unmodifiableMap(objectMapper.readValue(raw, MAP_TYPE));
        } catch (JsonProcessingException exception) {
            return Map.of();
        }
    }

    private static ComplaintRecord mapComplaint(ResultSet rs, int rowNum) throws SQLException {
        return new ComplaintRecord(
            rs.getObject("id", UUID.class),
            rs.getString("code"),
            rs.getObject("reporter_id", UUID.class),
            rs.getString("reporter_name"),
            rs.getString("reporter_email"),
            rs.getObject("category_id", UUID.class),
            rs.getString("category_name"),
            rs.getString("category_theme"),
            rs.getBoolean("category_is_sensitive"),
            rs.getString("category_photo_policy"),
            rs.getObject("location_id", UUID.class),
            rs.getString("location_name"),
            rs.getString("location_path"),
            rs.getString("title"),
            rs.getString("description"),
            rs.getString("severity"),
            rs.getString("status"),
            rs.getObject("department_id", UUID.class),
            rs.getString("department_name"),
            rs.getString("department_code"),
            rs.getString("department_kind"),
            rs.getObject("department_head_user_id", UUID.class),
            rs.getObject("assigned_to", UUID.class),
            rs.getString("assignee_name"),
            toInstant(rs.getObject("sla_due_at", OffsetDateTime.class)),
            rs.getInt("escalation_level"),
            rs.getInt("reopen_count"),
            rs.getInt("version"),
            rs.getString("idempotency_key"),
            toInstant(rs.getObject("created_at", OffsetDateTime.class)),
            toInstant(rs.getObject("updated_at", OffsetDateTime.class)),
            toInstant(rs.getObject("resolved_at", OffsetDateTime.class)),
            toInstant(rs.getObject("verified_at", OffsetDateTime.class)));
    }

    private static Instant toInstant(OffsetDateTime value) {
        return value == null ? null : value.toInstant();
    }

    public record PagedResult(List<ComplaintRecord> items, long totalElements) {
    }

    public record TransitionRuleRecord(
            String fromStatus,
            String toStatus,
            List<String> allowedRoles,
            boolean requiresNote,
            boolean systemOnly) {
    }

    public record ComplaintEventRecord(
            long id,
            UUID complaintId,
            UUID actorId,
            String actorRole,
            String actorName,
            String eventType,
            String fromStatus,
            String toStatus,
            Map<String, Object> payload,
            Instant createdAt) {
    }
}
