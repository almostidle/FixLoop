package com.fixloop.complaint;

import java.util.List;

import com.fixloop.auth.UserAccount;
import com.fixloop.complaint.dto.ComplaintAttachmentResponse;
import com.fixloop.complaint.dto.ComplaintDetailResponse;
import com.fixloop.complaint.dto.ComplaintEventResponse;
import com.fixloop.complaint.dto.ComplaintSummaryResponse;
import com.fixloop.complaint.dto.ReporterSummary;
import com.fixloop.storage.AttachmentRepository.AttachmentRecord;
import org.springframework.stereotype.Component;

/** Maps persistence records to role-safe response DTOs without leaking reporter identities. */
@Component
public class ComplaintMapper {
    private final ComplaintAccessPolicy accessPolicy;

    public ComplaintMapper(ComplaintAccessPolicy accessPolicy) {
        this.accessPolicy = accessPolicy;
    }

    public ComplaintSummaryResponse toSummary(ComplaintRecord c, UserAccount caller) {
        boolean isMine = c.reporterId().equals(caller.id());
        ReporterSummary reporter = accessPolicy.canSeeReporterIdentity(caller, c)
            ? new ReporterSummary(c.reporterId(), c.reporterName(), c.reporterEmail())
            : null;
        return new ComplaintSummaryResponse(
            c.id(),
            c.code(),
            c.title(),
            c.description(),
            c.severity(),
            c.status(),
            c.categoryId(),
            c.categoryName(),
            c.categoryTheme(),
            c.categoryIsSensitive(),
            c.categoryPhotoPolicy(),
            c.locationId(),
            c.locationName(),
            c.locationPath(),
            c.departmentId(),
            c.departmentName(),
            c.departmentCode(),
            c.assignedTo(),
            c.assigneeName(),
            c.slaDueAt(),
            c.escalationLevel(),
            c.reopenCount(),
            c.version(),
            isMine,
            reporter,
            c.createdAt(),
            c.updatedAt(),
            c.resolvedAt(),
            c.verifiedAt());
    }

    public ComplaintDetailResponse toDetail(ComplaintRecord c, UserAccount caller,
                                            List<ComplaintRepository.ComplaintEventRecord> events,
                                            List<AttachmentRecord> attachments) {
        boolean isMine = c.reporterId().equals(caller.id());
        ReporterSummary reporter = accessPolicy.canSeeReporterIdentity(caller, c)
            ? new ReporterSummary(c.reporterId(), c.reporterName(), c.reporterEmail())
            : null;
        List<ComplaintEventResponse> eventDtos = events.stream()
            .map(event -> new ComplaintEventResponse(
                event.id(),
                event.actorRole(),
                accessPolicy.canSeeActorIdentity(caller, event.actorId(), event.actorRole())
                    ? event.actorName() : null,
                event.eventType(),
                event.fromStatus(),
                event.toStatus(),
                event.payload(),
                event.createdAt()))
            .toList();
        List<ComplaintAttachmentResponse> attachmentDtos = attachments.stream()
            .map(att -> new ComplaintAttachmentResponse(
                att.id(),
                att.eventId(),
                att.kind(),
                att.storageKey(),
                att.mimeType(),
                att.sizeBytes(),
                att.createdAt()))
            .toList();
        return new ComplaintDetailResponse(
            c.id(),
            c.code(),
            c.title(),
            c.description(),
            c.severity(),
            c.status(),
            c.categoryId(),
            c.categoryName(),
            c.categoryTheme(),
            c.categoryIsSensitive(),
            c.categoryPhotoPolicy(),
            c.locationId(),
            c.locationName(),
            c.locationPath(),
            c.departmentId(),
            c.departmentName(),
            c.departmentCode(),
            c.assignedTo(),
            c.assigneeName(),
            c.slaDueAt(),
            c.escalationLevel(),
            c.reopenCount(),
            c.version(),
            isMine,
            reporter,
            c.createdAt(),
            c.updatedAt(),
            c.resolvedAt(),
            c.verifiedAt(),
            eventDtos,
            attachmentDtos);
    }
}
