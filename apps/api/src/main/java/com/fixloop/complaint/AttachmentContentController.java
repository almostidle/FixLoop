package com.fixloop.complaint;

import java.util.UUID;

import com.fixloop.auth.AuthPrincipal;
import com.fixloop.storage.AttachmentLinkService;
import com.fixloop.storage.AttachmentRepository.AttachmentRecord;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** Streams attachment photograph bytes after enforcing parent complaint visibility. */
@RestController
@RequestMapping("/api/v1/attachments")
public class AttachmentContentController {
    private final AttachmentLinkService attachmentLinks;
    private final ComplaintService complaints;

    public AttachmentContentController(AttachmentLinkService attachmentLinks,
                                       ComplaintService complaints) {
        this.attachmentLinks = attachmentLinks;
        this.complaints = complaints;
    }

    @GetMapping("/{id}/content")
    public ResponseEntity<byte[]> download(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID id) {
        AttachmentRecord metadata = attachmentLinks.requireMetadata(id);
        complaints.requireAttachmentAccess(AuthPrincipal.userId(jwt), metadata.complaintId());
        byte[] content = attachmentLinks.loadBytesOrMissing(metadata);

        MediaType mediaType = MediaType.APPLICATION_OCTET_STREAM;
        try {
            mediaType = MediaType.parseMediaType(metadata.mimeType());
        } catch (IllegalArgumentException ignored) {
            // Fall back to octet-stream if stored mime_type is unexpectedly malformed.
        }

        return ResponseEntity.ok()
            .contentType(mediaType)
            .cacheControl(CacheControl.noStore())
            .header("X-Content-Type-Options", "nosniff")
            .body(content);
    }
}
