package com.fixloop.storage;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

/** Persistence for attachment metadata linked to complaints and resolution events. */
@Repository
public class AttachmentRepository {
    private static final RowMapper<AttachmentRecord> MAPPER = AttachmentRepository::mapRow;

    private final JdbcTemplate jdbc;

    public AttachmentRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public Optional<AttachmentRecord> findById(UUID id) {
        List<AttachmentRecord> rows = jdbc.query(
            "SELECT id, complaint_id, event_id, kind, storage_key, mime_type, size_bytes, created_at "
                + "FROM attachments WHERE id = ?",
            MAPPER, id);
        return rows.stream().findFirst();
    }

    public List<AttachmentRecord> findByComplaintId(UUID complaintId) {
        return jdbc.query(
            "SELECT id, complaint_id, event_id, kind, storage_key, mime_type, size_bytes, created_at "
                + "FROM attachments WHERE complaint_id = ? ORDER BY created_at ASC",
            MAPPER, complaintId);
    }

    public boolean isKeyLinked(String storageKey) {
        Integer count = jdbc.queryForObject(
            "SELECT count(*) FROM attachments WHERE storage_key = ?",
            Integer.class, storageKey);
        return count != null && count > 0;
    }

    public AttachmentRecord insert(UUID complaintId, Long eventId, String kind,
                                   String storageKey, String mimeType, long sizeBytes) {
        return jdbc.queryForObject(
            "INSERT INTO attachments (complaint_id, event_id, kind, storage_key, mime_type, size_bytes) "
                + "VALUES (?, ?, ?, ?, ?, ?) "
                + "RETURNING id, complaint_id, event_id, kind, storage_key, mime_type, size_bytes, created_at",
            MAPPER, complaintId, eventId, kind, storageKey, mimeType, sizeBytes);
    }

    private static AttachmentRecord mapRow(ResultSet rs, int rowNumber) throws SQLException {
        long eventIdVal = rs.getLong("event_id");
        Long eventId = rs.wasNull() ? null : eventIdVal;
        OffsetDateTime created = rs.getObject("created_at", OffsetDateTime.class);
        return new AttachmentRecord(
            rs.getObject("id", UUID.class),
            rs.getObject("complaint_id", UUID.class),
            eventId,
            rs.getString("kind"),
            rs.getString("storage_key"),
            rs.getString("mime_type"),
            rs.getLong("size_bytes"),
            created == null ? Instant.now() : created.toInstant());
    }

    public record AttachmentRecord(
            UUID id,
            UUID complaintId,
            Long eventId,
            String kind,
            String storageKey,
            String mimeType,
            long sizeBytes,
            Instant createdAt) {
    }
}
