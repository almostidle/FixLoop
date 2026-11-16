package com.fixloop.directory;

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import com.fixloop.auth.Role;
import com.fixloop.auth.UserAccount;
import com.fixloop.directory.dto.CategoryResponse;
import com.fixloop.directory.dto.DepartmentResponse;
import com.fixloop.directory.dto.LocationResponse;
import com.fixloop.directory.dto.StaffMemberResponse;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

/** Plain-SQL queries for campus reference data (categories, locations, departments, staff). */
@Repository
public class DirectoryRepository {
    private static final RowMapper<CategoryResponse> CATEGORY_MAPPER = (rs, rowNum) -> new CategoryResponse(
        rs.getObject("id", UUID.class),
        rs.getString("name"),
        rs.getString("theme"),
        rs.getString("default_severity"),
        rs.getString("photo_policy"),
        rs.getBoolean("is_sensitive"),
        rs.getInt("sort_order"));

    private static final RowMapper<LocationResponse> LOCATION_MAPPER = (rs, rowNum) -> new LocationResponse(
        rs.getObject("id", UUID.class),
        rs.getObject("parent_id", UUID.class),
        rs.getString("type"),
        rs.getString("name"),
        rs.getString("path"));

    private static final RowMapper<DepartmentResponse> DEPARTMENT_MAPPER = (rs, rowNum) -> new DepartmentResponse(
        rs.getObject("id", UUID.class),
        rs.getString("name"),
        rs.getString("code"),
        rs.getString("kind"),
        rs.getObject("head_user_id", UUID.class));

    private static final RowMapper<StaffMemberResponse> STAFF_MAPPER = (rs, rowNum) -> new StaffMemberResponse(
        rs.getObject("id", UUID.class),
        rs.getString("full_name"),
        rs.getString("email"),
        Role.valueOf(rs.getString("role")),
        rs.getObject("department_id", UUID.class),
        rs.getString("department_name"),
        rs.getObject("scope_location_id", UUID.class));

    private final JdbcTemplate jdbc;

    public DirectoryRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public List<CategoryResponse> findActiveCategories() {
        return jdbc.query(
            "SELECT id, name, theme, default_severity, photo_policy, is_sensitive, sort_order "
                + "FROM categories WHERE active = true ORDER BY sort_order ASC, name ASC",
            CATEGORY_MAPPER);
    }

    public Optional<CategoryResponse> findActiveCategoryById(UUID id) {
        List<CategoryResponse> rows = jdbc.query(
            "SELECT id, name, theme, default_severity, photo_policy, is_sensitive, sort_order "
                + "FROM categories WHERE id = ? AND active = true",
            CATEGORY_MAPPER, id);
        return rows.stream().findFirst();
    }

    public List<LocationResponse> findActiveLocations(UUID parentId) {
        if (parentId != null) {
            return jdbc.query(
                "SELECT id, parent_id, type, name, path FROM locations "
                    + "WHERE active = true AND parent_id = ? ORDER BY path ASC",
                LOCATION_MAPPER, parentId);
        }
        return jdbc.query(
            "SELECT id, parent_id, type, name, path FROM locations "
                + "WHERE active = true ORDER BY path ASC",
            LOCATION_MAPPER);
    }

    public Optional<LocationResponse> findActiveLocationById(UUID id) {
        List<LocationResponse> rows = jdbc.query(
            "SELECT id, parent_id, type, name, path FROM locations "
                + "WHERE id = ? AND active = true",
            LOCATION_MAPPER, id);
        return rows.stream().findFirst();
    }

    public Optional<LocationResponse> findLocationById(UUID id) {
        List<LocationResponse> rows = jdbc.query(
            "SELECT id, parent_id, type, name, path FROM locations WHERE id = ?",
            LOCATION_MAPPER, id);
        return rows.stream().findFirst();
    }

    public List<DepartmentResponse> findVisibleActiveDepartments(UserAccount caller) {
        if (caller.role() == Role.ADMIN || caller.role() == Role.SUPERVISOR) {
            return jdbc.query(
                "SELECT id, name, code, kind, head_user_id FROM departments "
                    + "WHERE active = true ORDER BY name ASC",
                DEPARTMENT_MAPPER);
        }
        if (caller.departmentId() != null) {
            return jdbc.query(
                "SELECT id, name, code, kind, head_user_id FROM departments "
                    + "WHERE active = true AND (kind = 'SERVICE' OR id = ?) ORDER BY name ASC",
                DEPARTMENT_MAPPER, caller.departmentId());
        }
        return jdbc.query(
            "SELECT id, name, code, kind, head_user_id FROM departments "
                + "WHERE active = true AND kind = 'SERVICE' ORDER BY name ASC",
            DEPARTMENT_MAPPER);
    }

    public Optional<DepartmentResponse> findActiveDepartmentById(UUID id) {
        List<DepartmentResponse> rows = jdbc.query(
            "SELECT id, name, code, kind, head_user_id FROM departments "
                + "WHERE id = ? AND active = true",
            DEPARTMENT_MAPPER, id);
        return rows.stream().findFirst();
    }

    public List<StaffMemberResponse> findActiveStaffUsers(UserAccount caller, UUID departmentId) {
        StringBuilder sql = new StringBuilder(
            "SELECT u.id, u.full_name, u.email, u.role, u.department_id, d.name AS department_name, u.scope_location_id "
                + "FROM users u "
                + "LEFT JOIN departments d ON d.id = u.department_id "
                + "WHERE u.active = true AND u.role IN ('STAFF', 'SUPERVISOR')");
        List<Object> params = new ArrayList<>();
        if (departmentId != null) {
            sql.append(" AND u.department_id = ?");
            params.add(departmentId);
        }
        if (caller.role() != Role.ADMIN) {
            if (caller.departmentId() != null) {
                sql.append(" AND (d.kind = 'SERVICE' OR u.department_id = ?)");
                params.add(caller.departmentId());
            } else {
                sql.append(" AND d.kind = 'SERVICE'");
            }
        }
        sql.append(" ORDER BY u.role DESC, u.full_name ASC");
        return jdbc.query(sql.toString(), STAFF_MAPPER, params.toArray());
    }
}
