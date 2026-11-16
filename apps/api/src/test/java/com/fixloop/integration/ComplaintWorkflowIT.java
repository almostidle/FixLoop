package com.fixloop.integration;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * Full end-to-end integration test across reference directory, attachment
 * upload/download, auto-routing, SLA computation, idempotency, sensitive
 * category isolation, optimistic locking, full workflow transitions, notes,
 * notifications, and analytics views against PostgreSQL 16.
 */
@Testcontainers
@ActiveProfiles("integration-test")
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
    properties = {
        "fixloop.auth.rate-limit-enabled=false",
        "fixloop.auth.allowed-email-domains=bmu.edu.in"
    })
class ComplaintWorkflowIT {
    private static final String PASSWORD = "campus-lamp-2026";

    private static final Path STORAGE_DIR;

    static {
        try {
            STORAGE_DIR = Files.createTempDirectory("fixloop-workflow-it-");
        } catch (IOException exception) {
            throw new ExceptionInInitializerError(exception);
        }
    }

    @Container
    static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:16-alpine");

    @DynamicPropertySource
    static void properties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
        registry.add("spring.datasource.hikari.data-source-properties.sslmode", () -> "disable");
        registry.add("spring.flyway.enabled", () -> true);
        registry.add("fixloop.storage.root", () -> STORAGE_DIR.toString());
    }

    @Autowired
    private TestRestTemplate http;

    @Autowired
    private JdbcTemplate jdbc;

    @Autowired
    private PasswordEncoder passwordEncoder;

    private UUID deptFacId;
    private UUID deptItId;
    private UUID deptIccId;

    private UUID locCampusId;
    private UUID locHostelId;
    private UUID locRoomId;

    private UUID catPlumbingId;
    private UUID catWifiId;
    private UUID catSensitiveId;

    private UUID student1Id;
    private UUID student2Id;
    private UUID staffFacId;
    private UUID supFacId;
    private UUID staffIccId;
    private UUID adminId;

    @BeforeEach
    void seedCampusData() {
        String hash = passwordEncoder.encode(PASSWORD);

        deptFacId = UUID.randomUUID();
        deptItId = UUID.randomUUID();
        deptIccId = UUID.randomUUID();

        jdbc.update("INSERT INTO departments (id, name, code, kind) VALUES (?, 'Facilities & Maintenance', 'FAC', 'SERVICE')", deptFacId);
        jdbc.update("INSERT INTO departments (id, name, code, kind) VALUES (?, 'IT & Network Services', 'IT', 'SERVICE')", deptItId);
        jdbc.update("INSERT INTO departments (id, name, code, kind) VALUES (?, 'Internal Complaints Committee', 'ICC', 'RESTRICTED')", deptIccId);

        locCampusId = UUID.randomUUID();
        locHostelId = UUID.randomUUID();
        locRoomId = UUID.randomUUID();

        jdbc.update("INSERT INTO locations (id, parent_id, type, name, path) VALUES (?, NULL, 'CAMPUS', 'BML Munjal Campus', '/bmu')", locCampusId);
        jdbc.update("INSERT INTO locations (id, parent_id, type, name, path) VALUES (?, ?, 'BLOCK', 'Boys Hostel T1', '/bmu/boys-hostel-t1')", locHostelId, locCampusId);
        jdbc.update("INSERT INTO locations (id, parent_id, type, name, path) VALUES (?, ?, 'ROOM', 'Room 204', '/bmu/boys-hostel-t1/room-204')", locRoomId, locHostelId);

        catPlumbingId = UUID.randomUUID();
        catWifiId = UUID.randomUUID();
        catSensitiveId = UUID.randomUUID();

        jdbc.update("INSERT INTO categories (id, name, theme, default_severity, photo_policy, is_sensitive, sort_order) "
            + "VALUES (?, 'Plumbing & Water Supply', 'INFRASTRUCTURE', 'HIGH', 'REQUIRED', false, 1)", catPlumbingId);
        jdbc.update("INSERT INTO categories (id, name, theme, default_severity, photo_policy, is_sensitive, sort_order) "
            + "VALUES (?, 'Wi-Fi & Campus Network', 'IT', 'MEDIUM', 'OPTIONAL', false, 2)", catWifiId);
        jdbc.update("INSERT INTO categories (id, name, theme, default_severity, photo_policy, is_sensitive, sort_order) "
            + "VALUES (?, 'Harassment & Sensitive Grievance', 'SENSITIVE', 'CRITICAL', 'DISABLED', true, 3)", catSensitiveId);

        student1Id = insertUser("student1@bmu.edu.in", hash, "Aarav Mehta", "STUDENT", null, null);
        student2Id = insertUser("student2@bmu.edu.in", hash, "Priya Sharma", "STUDENT", null, null);
        staffFacId = insertUser("tech.fac@bmu.edu.in", hash, "Ramesh Kumar", "STAFF", deptFacId, null);
        supFacId = insertUser("head.fac@bmu.edu.in", hash, "Anil Kapoor", "SUPERVISOR", deptFacId, locCampusId);
        staffIccId = insertUser("chair.icc@bmu.edu.in", hash, "Dr. Meera Iyer", "SUPERVISOR", deptIccId, locCampusId);
        adminId = insertUser("admin@bmu.edu.in", hash, "Campus Admin", "ADMIN", null, null);

        jdbc.update("UPDATE departments SET head_user_id = ? WHERE id = ?", supFacId, deptFacId);
        jdbc.update("UPDATE departments SET head_user_id = ? WHERE id = ?", staffIccId, deptIccId);

        jdbc.update("INSERT INTO routing_rules (priority, category_id, department_id, note) VALUES (1, ?, ?, 'Sensitive to ICC')",
            catSensitiveId, deptIccId);
        jdbc.update("INSERT INTO routing_rules (priority, category_id, location_scope_id, department_id, note) VALUES (10, ?, ?, ?, 'Hostel plumbing')",
            catPlumbingId, locHostelId, deptFacId);
        jdbc.update("INSERT INTO routing_rules (priority, category_id, department_id, note) VALUES (999, NULL, ?, 'Fallback FAC')",
            deptFacId);

        jdbc.update("INSERT INTO sla_policies (category_id, severity, response_minutes, resolve_minutes) VALUES (NULL, 'HIGH', 120, 720)");
        jdbc.update("INSERT INTO sla_policies (category_id, severity, response_minutes, resolve_minutes) VALUES (NULL, 'MEDIUM', 240, 2880)");
        jdbc.update("INSERT INTO sla_policies (category_id, severity, response_minutes, resolve_minutes) VALUES (NULL, 'CRITICAL', 30, 240)");
    }

    @Test
    @SuppressWarnings("unchecked")
    void endToEndComplaintWorkflowAndPrivacyAndAnalytics() {
        String s1Token = login("student1@bmu.edu.in");
        String s2Token = login("student2@bmu.edu.in");
        String facStaffToken = login("tech.fac@bmu.edu.in");
        String facSupToken = login("head.fac@bmu.edu.in");
        String iccToken = login("chair.icc@bmu.edu.in");
        String adminToken = login("admin@bmu.edu.in");

        // 1. Directory reference data & restricted department hiding.
        ResponseEntity<List> studentDepts = getList("/api/v1/departments", s1Token);
        assertThat(studentDepts.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(studentDepts.getBody()).hasSize(2);
        assertThat(getList("/api/v1/departments", facSupToken).getBody()).hasSize(3);
        assertThat(getForMap("/api/v1/users/staff", s1Token).getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
        assertThat(getList("/api/v1/users/staff?departmentId=" + deptFacId, facSupToken).getBody()).hasSize(2);

        // 2. Photo policy enforcement (REQUIRED on plumbing).
        ResponseEntity<Map> missingPhoto = postJson("/api/v1/complaints", s1Token, null, Map.of(
            "categoryId", catPlumbingId.toString(),
            "locationId", locRoomId.toString(),
            "title", "Water leak near Room 204",
            "description", "Pipe leaking constantly."
        ));
        assertThat(missingPhoto.getStatusCode()).isEqualTo(HttpStatus.UNPROCESSABLE_ENTITY);
        assertThat(missingPhoto.getBody()).containsEntry("code", "PHOTO_REQUIRED");

        // 3. Upload photo & create complaint with Idempotency-Key replay.
        String reportPhotoKey = uploadPng(s1Token);
        String idemKey = "idem-" + UUID.randomUUID();
        Map<String, Object> createPayload = Map.of(
            "categoryId", catPlumbingId.toString(),
            "locationId", locRoomId.toString(),
            "title", "Leaking ceiling pipe in Room 204",
            "description", "Steady drip onto study desk.",
            "attachmentKeys", List.of(reportPhotoKey)
        );
        ResponseEntity<Map> created = postJson("/api/v1/complaints", s1Token, idemKey, createPayload);
        assertThat(created.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        String complaintId = (String) created.getBody().get("id");
        String code = (String) created.getBody().get("code");
        assertThat(code).matches("FL-\\d{4}-\\d{6}");
        assertThat(created.getBody()).containsEntry("status", "ASSIGNED");
        assertThat(created.getBody()).containsEntry("departmentCode", "FAC");
        assertThat(created.getBody()).containsEntry("version", 1);
        assertThat(created.getBody().get("slaDueAt")).isNotNull();

        List<Map<String, Object>> attachments = (List<Map<String, Object>>) created.getBody().get("attachments");
        assertThat(attachments).hasSize(1);
        String attachmentId = (String) attachments.get(0).get("id");

        // Idempotent replay returns same id & code.
        ResponseEntity<Map> replayed = postJson("/api/v1/complaints", s1Token, idemKey, createPayload);
        assertThat(replayed.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        assertThat(replayed.getBody()).containsEntry("id", complaintId).containsEntry("code", code);

        // Attachment bytes download works for authorized user, returns exact bytes.
        ResponseEntity<byte[]> downloaded = exchangeBytes("/api/v1/attachments/" + attachmentId + "/content", facStaffToken);
        assertThat(downloaded.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(downloaded.getBody()).isEqualTo(pngBytes());

        // Similar open issues endpoint counts the non-sensitive complaint.
        ResponseEntity<Map> similar = getForMap(
            "/api/v1/complaints/similar?locationId=" + locRoomId + "&categoryId=" + catPlumbingId, s2Token);
        assertThat(similar.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(((Number) similar.getBody().get("count")).longValue()).isEqualTo(1L);

        // Reporter anonymity: student2 & facStaff see the issue without reporter object.
        ResponseEntity<Map> s2View = getForMap("/api/v1/complaints/" + complaintId, s2Token);
        assertThat(s2View.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(s2View.getBody()).doesNotContainKey("reporter");
        assertThat(getForMap("/api/v1/complaints/" + complaintId, adminToken).getBody()).containsKey("reporter");

        // 4. Sensitive complaint isolation & photo DISABLED policy.
        ResponseEntity<Map> sensitiveWithPhoto = postJson("/api/v1/complaints", s1Token, null, Map.of(
            "categoryId", catSensitiveId.toString(),
            "locationId", locCampusId.toString(),
            "title", "Confidential grievance report",
            "attachmentKeys", List.of(uploadPng(s1Token))
        ));
        assertThat(sensitiveWithPhoto.getStatusCode()).isEqualTo(HttpStatus.UNPROCESSABLE_ENTITY);
        assertThat(sensitiveWithPhoto.getBody()).containsEntry("code", "PHOTO_NOT_ALLOWED");

        ResponseEntity<Map> sensitiveCreated = postJson("/api/v1/complaints", s1Token, null, Map.of(
            "categoryId", catSensitiveId.toString(),
            "locationId", locCampusId.toString(),
            "title", "Confidential grievance report",
            "description", "Private details."
        ));
        assertThat(sensitiveCreated.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        String sensitiveId = (String) sensitiveCreated.getBody().get("id");
        assertThat(sensitiveCreated.getBody()).containsEntry("departmentCode", "ICC");

        // Other student & Facilities supervisor/staff CANNOT access sensitive report.
        assertThat(getForMap("/api/v1/complaints/" + sensitiveId, s2Token).getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
        assertThat(getForMap("/api/v1/complaints/" + sensitiveId, facSupToken).getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
        assertThat(getForMap("/api/v1/complaints/" + sensitiveId, iccToken).getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(getForMap("/api/v1/complaints/" + sensitiveId, iccToken).getBody()).doesNotContainKey("reporter");
        assertThat(getForMap("/api/v1/complaints/" + sensitiveId, adminToken).getBody()).containsKey("reporter");

        // 5. Full staff -> supervisor -> student workflow + optimistic lock conflict.
        // Claim (ASSIGNED -> IN_PROGRESS)
        ResponseEntity<Map> claimed = postJson("/api/v1/complaints/" + complaintId + "/transition", facStaffToken, null, Map.of(
            "toStatus", "IN_PROGRESS",
            "version", 1
        ));
        assertThat(claimed.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(claimed.getBody()).containsEntry("status", "IN_PROGRESS").containsEntry("version", 2);

        // Stale version fails with 409 VERSION_CONFLICT.
        ResponseEntity<Map> staleClaim = postJson("/api/v1/complaints/" + complaintId + "/transition", facStaffToken, null, Map.of(
            "toStatus", "RESOLVED",
            "version", 1,
            "note", "Stale attempt"
        ));
        assertThat(staleClaim.getStatusCode()).isEqualTo(HttpStatus.CONFLICT);
        assertThat(staleClaim.getBody()).containsEntry("code", "VERSION_CONFLICT");

        // Add note & resolve with a resolution photo.
        ResponseEntity<Map> noted = postJson("/api/v1/complaints/" + complaintId + "/notes", facStaffToken, null, Map.of(
            "note", "Shut off valve and ordering elbow joint."
        ));
        assertThat(noted.getStatusCode()).isEqualTo(HttpStatus.OK);

        String resolutionPhotoKey = uploadPng(facStaffToken);
        ResponseEntity<Map> resolved = postJson("/api/v1/complaints/" + complaintId + "/transition", facStaffToken, null, Map.of(
            "toStatus", "RESOLVED",
            "version", 2,
            "note", "Replaced damaged elbow joint and tested line.",
            "attachmentKeys", List.of(resolutionPhotoKey)
        ));
        assertThat(resolved.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(resolved.getBody()).containsEntry("status", "RESOLVED").containsEntry("version", 3);
        assertThat((List<?>) resolved.getBody().get("attachments")).hasSize(2);

        // Student2 cannot verify Student1's complaint.
        assertThat(postJson("/api/v1/complaints/" + complaintId + "/transition", s2Token, null, Map.of(
            "toStatus", "VERIFIED",
            "version", 3
        )).getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);

        // Student1 reopens -> immediately auto-routes REOPENED -> ASSIGNED (reopenCount = 1).
        ResponseEntity<Map> reopened = postJson("/api/v1/complaints/" + complaintId + "/transition", s1Token, null, Map.of(
            "toStatus", "REOPENED",
            "version", 3,
            "note", "Small drip returned after 10 minutes."
        ));
        assertThat(reopened.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(reopened.getBody()).containsEntry("status", "ASSIGNED").containsEntry("reopenCount", 1);
        int reopenedVersion = ((Number) reopened.getBody().get("version")).intValue();

        // Staff re-claims & resolves; student1 verifies.
        ResponseEntity<Map> reclaimed = postJson("/api/v1/complaints/" + complaintId + "/transition", facStaffToken, null, Map.of(
            "toStatus", "IN_PROGRESS",
            "version", reopenedVersion
        ));
        int claimedVer = ((Number) reclaimed.getBody().get("version")).intValue();
        ResponseEntity<Map> reResolved = postJson("/api/v1/complaints/" + complaintId + "/transition", facStaffToken, null, Map.of(
            "toStatus", "RESOLVED",
            "version", claimedVer,
            "note", "Tightened coupling and sealed joint."
        ));
        int resolvedVer = ((Number) reResolved.getBody().get("version")).intValue();
        ResponseEntity<Map> verified = postJson("/api/v1/complaints/" + complaintId + "/transition", s1Token, null, Map.of(
            "toStatus", "VERIFIED",
            "version", resolvedVer
        ));
        assertThat(verified.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(verified.getBody()).containsEntry("status", "VERIFIED");
        assertThat(verified.getBody().get("verifiedAt")).isNotNull();

        // 6. Seeded attachment row lacking disk file returns clean 404 ATTACHMENT_FILE_MISSING.
        UUID missingFileAttId = UUID.randomUUID();
        jdbc.update("INSERT INTO attachments (id, complaint_id, kind, storage_key, mime_type, size_bytes) "
            + "VALUES (?, ?, 'REPORT', 'complaints/2026/10/seeded-missing.jpg', 'image/jpeg', 12345)",
            missingFileAttId, UUID.fromString(complaintId));
        ResponseEntity<Map> missingFileResp = getForMap("/api/v1/attachments/" + missingFileAttId + "/content", s1Token);
        assertThat(missingFileResp.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        assertThat(missingFileResp.getBody()).containsEntry("code", "ATTACHMENT_FILE_MISSING");

        // 7. Notifications & Analytics summary.
        ResponseEntity<Map> studentNotifs = getForMap("/api/v1/notifications", s1Token);
        assertThat(studentNotifs.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(((Number) studentNotifs.getBody().get("unreadCount")).longValue()).isGreaterThan(0L);
        List<Map<String, Object>> notifItems = (List<Map<String, Object>>) studentNotifs.getBody().get("items");
        String firstNotifId = (String) notifItems.get(0).get("id");
        ResponseEntity<Map> readResp = postJson("/api/v1/notifications/" + firstNotifId + "/read", s1Token, null, Map.of());
        assertThat(readResp.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(readResp.getBody().get("readAt")).isNotNull();

        ResponseEntity<Map> adminAnalytics = getForMap("/api/v1/analytics/summary", adminToken);
        assertThat(adminAnalytics.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(((Number) adminAnalytics.getBody().get("totalComplaints")).longValue()).isEqualTo(2L);
        assertThat(((List<?>) adminAnalytics.getBody().get("byDepartment"))).hasSize(1); // ICC still open

        ResponseEntity<Map> studentAnalytics = getForMap("/api/v1/analytics/summary", s1Token);
        assertThat(studentAnalytics.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat((List<?>) studentAnalytics.getBody().get("byDepartment")).isEmpty();
    }

    private UUID insertUser(String email, String hash, String fullName, String role,
                            UUID departmentId, UUID scopeLocationId) {
        return jdbc.queryForObject(
            "INSERT INTO users (email, password_hash, full_name, role, department_id, scope_location_id) "
                + "VALUES (?, ?, ?, ?, ?, ?) RETURNING id",
            UUID.class, email, hash, fullName, role, departmentId, scopeLocationId);
    }

    @SuppressWarnings("unchecked")
    private String login(String email) {
        ResponseEntity<Map> response = http.postForEntity("/api/v1/auth/login",
            Map.of("email", email, "password", PASSWORD), Map.class);
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        return (String) response.getBody().get("accessToken");
    }

    @SuppressWarnings("unchecked")
    private String uploadPng(String token) {
        HttpHeaders headers = new HttpHeaders();
        headers.setBearerAuth(token);
        headers.setContentType(MediaType.MULTIPART_FORM_DATA);

        ByteArrayResource resource = new ByteArrayResource(pngBytes()) {
            @Override
            public String getFilename() {
                return "evidence.png";
            }
        };
        HttpHeaders partHeaders = new HttpHeaders();
        partHeaders.setContentType(MediaType.IMAGE_PNG);
        MultiValueMap<String, Object> body = new LinkedMultiValueMap<>();
        body.add("file", new HttpEntity<>(resource, partHeaders));

        ResponseEntity<Map> response = http.exchange("/api/v1/attachments", HttpMethod.POST,
            new HttpEntity<>(body, headers), Map.class);
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        return (String) response.getBody().get("storageKey");
    }

    private ResponseEntity<Map> postJson(String path, String token, String idempotencyKey, Map<String, Object> body) {
        HttpHeaders headers = new HttpHeaders();
        headers.setBearerAuth(token);
        headers.setContentType(MediaType.APPLICATION_JSON);
        if (idempotencyKey != null) {
            headers.set("Idempotency-Key", idempotencyKey);
        }
        return http.exchange(path, HttpMethod.POST, new HttpEntity<>(body, headers), Map.class);
    }

    private ResponseEntity<Map> getForMap(String path, String token) {
        HttpHeaders headers = new HttpHeaders();
        headers.setBearerAuth(token);
        return http.exchange(path, HttpMethod.GET, new HttpEntity<>(headers), Map.class);
    }

    private ResponseEntity<List> getList(String path, String token) {
        HttpHeaders headers = new HttpHeaders();
        headers.setBearerAuth(token);
        return http.exchange(path, HttpMethod.GET, new HttpEntity<>(headers), List.class);
    }

    private ResponseEntity<byte[]> exchangeBytes(String path, String token) {
        HttpHeaders headers = new HttpHeaders();
        headers.setBearerAuth(token);
        return http.exchange(path, HttpMethod.GET, new HttpEntity<>(headers), byte[].class);
    }

    private static byte[] pngBytes() {
        byte[] content = new byte[64];
        content[0] = (byte) 0x89;
        content[1] = 'P';
        content[2] = 'N';
        content[3] = 'G';
        content[4] = 0x0D;
        content[5] = 0x0A;
        content[6] = 0x1A;
        content[7] = 0x0A;
        return content;
    }
}
