package com.fixloop.notification;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fixloop.notification.dto.NotificationResponse;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

/** Reads and inserts {@code IN_APP} rows in {@code notifications_outbox}. */
@Repository
public class NotificationRepository {
    private static final TypeReference<Map<String, Object>> MAP_TYPE = new TypeReference<>() {};

    private final JdbcTemplate jdbc;
    private final ObjectMapper objectMapper;
    private final RowMapper<NotificationResponse> mapper;

    public NotificationRepository(JdbcTemplate jdbc, ObjectMapper objectMapper) {
        this.jdbc = jdbc;
        this.objectMapper = objectMapper;
        this.mapper = this::mapRow;
    }

    public void insertInApp(UUID userId, String type, Map<String, Object> payload) {
        String json = toJson(payload);
        jdbc.update(
            "INSERT INTO notifications_outbox (user_id, channel, type, payload, status, sent_at) "
                + "VALUES (?, 'IN_APP', ?, ?::jsonb, 'SENT', now())",
            userId, type, json);
    }

    public List<NotificationResponse> findInAppForUser(UUID userId, int limit) {
        return jdbc.query(
            "SELECT id, type, payload::text AS payload_text, status, created_at, read_at "
                + "FROM notifications_outbox "
                + "WHERE user_id = ? AND channel = 'IN_APP' "
                + "ORDER BY created_at DESC LIMIT ?",
            mapper, userId, limit);
    }

    public long countUnreadInApp(UUID userId) {
        Long count = jdbc.queryForObject(
            "SELECT count(*) FROM notifications_outbox "
                + "WHERE user_id = ? AND channel = 'IN_APP' AND read_at IS NULL",
            Long.class, userId);
        return count == null ? 0L : count;
    }

    public Optional<NotificationResponse> markRead(UUID id, UUID userId) {
        List<NotificationResponse> rows = jdbc.query(
            "UPDATE notifications_outbox "
                + "SET read_at = COALESCE(read_at, now()) "
                + "WHERE id = ? AND user_id = ? AND channel = 'IN_APP' "
                + "RETURNING id, type, payload::text AS payload_text, status, created_at, read_at",
            mapper, id, userId);
        return rows.stream().findFirst();
    }

    private NotificationResponse mapRow(ResultSet rs, int rowNumber) throws SQLException {
        Map<String, Object> payload = parseJson(rs.getString("payload_text"));
        Object rawMessage = payload.get("message");
        String message = rawMessage == null ? "" : rawMessage.toString();
        UUID complaintId = parseUuid(payload.get("complaint_id"));
        OffsetDateTime createdAt = rs.getObject("created_at", OffsetDateTime.class);
        OffsetDateTime readAt = rs.getObject("read_at", OffsetDateTime.class);
        return new NotificationResponse(
            rs.getObject("id", UUID.class),
            rs.getString("type"),
            message,
            complaintId,
            rs.getString("status"),
            createdAt == null ? Instant.now() : createdAt.toInstant(),
            readAt == null ? null : readAt.toInstant(),
            payload);
    }

    private String toJson(Map<String, Object> payload) {
        try {
            return objectMapper.writeValueAsString(payload == null ? Map.of() : payload);
        } catch (JsonProcessingException exception) {
            throw new IllegalStateException("Could not serialize notification payload", exception);
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

    private static UUID parseUuid(Object value) {
        if (value == null) {
            return null;
        }
        try {
            return UUID.fromString(value.toString());
        } catch (IllegalArgumentException exception) {
            return null;
        }
    }
}
