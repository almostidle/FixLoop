package com.fixloop.storage;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import com.fixloop.auth.SettingsRepository;
import com.fixloop.common.ApiException;
import org.springframework.stereotype.Service;

/** Validates uploaded attachment keys, links them to complaints/events, and reads stored bytes. */
@Service
public class AttachmentLinkService {
    private static final int DEFAULT_MAX_ATTACHMENTS = 5;

    private final StorageBackend storage;
    private final AttachmentRepository attachments;
    private final SettingsRepository settings;

    public AttachmentLinkService(StorageBackend storage,
                                 AttachmentRepository attachments,
                                 SettingsRepository settings) {
        this.storage = storage;
        this.attachments = attachments;
        this.settings = settings;
    }

    public List<ValidatedAttachment> validateForComplaint(List<String> rawKeys) {
        if (rawKeys == null || rawKeys.isEmpty()) {
            return List.of();
        }
        Set<String> uniqueKeys = new LinkedHashSet<>();
        for (String raw : rawKeys) {
            if (raw == null || raw.isBlank()) {
                throw ApiException.badRequest("INVALID_ATTACHMENT_KEY", "Attachment keys must not be blank.");
            }
            uniqueKeys.add(raw.trim());
        }
        int maxAttachments = maxAttachmentsPerComplaint();
        if (uniqueKeys.size() > maxAttachments) {
            throw ApiException.unprocessable("TOO_MANY_ATTACHMENTS",
                "At most " + maxAttachments + " photos may be attached.");
        }

        List<ValidatedAttachment> validated = new ArrayList<>(uniqueKeys.size());
        for (String key : uniqueKeys) {
            if (!FilesystemStorage.isValidGeneratedKey(key)) {
                throw ApiException.badRequest("INVALID_ATTACHMENT_KEY",
                    "The attachment key format is not valid.");
            }
            byte[] bytes = storage.load(key)
                .orElseThrow(() -> ApiException.unprocessable("ATTACHMENT_NOT_FOUND",
                    "An uploaded photograph was not found. Please upload it again."));
            ImageType detected = ImageType.detect(bytes);
            if (detected == null) {
                throw ApiException.unprocessable("UNSUPPORTED_FILE_TYPE",
                    "Only JPEG, PNG and WebP photographs are accepted.");
            }
            if (attachments.isKeyLinked(key)) {
                throw ApiException.conflict("ATTACHMENT_ALREADY_LINKED",
                    "That uploaded photograph is already attached to a complaint.");
            }
            validated.add(new ValidatedAttachment(key, detected.mimeType(), bytes.length));
        }
        return validated;
    }

    public void linkAll(UUID complaintId, Long eventId, String kind, List<ValidatedAttachment> items) {
        for (ValidatedAttachment item : items) {
            attachments.insert(complaintId, eventId, kind, item.storageKey(), item.mimeType(), item.sizeBytes());
        }
    }

    public AttachmentRepository.AttachmentRecord requireMetadata(UUID attachmentId) {
        return attachments.findById(attachmentId)
            .orElseThrow(() -> ApiException.notFound("ATTACHMENT_NOT_FOUND",
                "The requested attachment does not exist."));
    }

    public byte[] loadBytesOrMissing(AttachmentRepository.AttachmentRecord record) {
        return storage.load(record.storageKey())
            .orElseThrow(() -> ApiException.notFound("ATTACHMENT_FILE_MISSING",
                "The attachment file is not present on storage."));
    }

    private int maxAttachmentsPerComplaint() {
        return settings.findValue("max_attachments_per_complaint")
            .map(value -> {
                try {
                    int parsed = Integer.parseInt(value.trim());
                    return parsed > 0 ? parsed : DEFAULT_MAX_ATTACHMENTS;
                } catch (NumberFormatException ignored) {
                    return DEFAULT_MAX_ATTACHMENTS;
                }
            })
            .orElse(DEFAULT_MAX_ATTACHMENTS);
    }

    public record ValidatedAttachment(String storageKey, String mimeType, long sizeBytes) {
    }
}
