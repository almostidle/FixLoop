package com.fixloop.complaint;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import com.fixloop.auth.AuthService;
import com.fixloop.auth.Role;
import com.fixloop.auth.UserAccount;
import com.fixloop.common.ApiException;
import com.fixloop.complaint.dto.AddNoteRequest;
import com.fixloop.complaint.dto.ComplaintDetailResponse;
import com.fixloop.complaint.dto.ComplaintPageResponse;
import com.fixloop.complaint.dto.ComplaintSummaryResponse;
import com.fixloop.complaint.dto.CreateComplaintRequest;
import com.fixloop.complaint.dto.SimilarComplaintsResponse;
import com.fixloop.complaint.dto.TransitionRequest;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Public service coordinating complaint intake, queries, workflow transitions, notes, and access control. */
@Service
public class ComplaintService {
    private static final int MAX_PAGE_SIZE = 100;
    private static final int MAX_IDEMPOTENCY_KEY_LENGTH = 100;

    private final ComplaintTxService txService;
    private final ComplaintRepository repository;
    private final ComplaintAccessPolicy accessPolicy;
    private final ComplaintMapper mapper;
    private final AuthService authService;

    public ComplaintService(ComplaintTxService txService,
                            ComplaintRepository repository,
                            ComplaintAccessPolicy accessPolicy,
                            ComplaintMapper mapper,
                            AuthService authService) {
        this.txService = txService;
        this.repository = repository;
        this.accessPolicy = accessPolicy;
        this.mapper = mapper;
        this.authService = authService;
    }

    public ComplaintDetailResponse create(UUID callerId, CreateComplaintRequest request, String rawIdempotencyKey) {
        UserAccount caller = authService.requireActiveUser(callerId);
        if (caller.role() != Role.STUDENT && caller.role() != Role.ADMIN) {
            throw ApiException.forbidden("FORBIDDEN",
                "Only students and administrators may submit complaints.");
        }

        String idempotencyKey = normalizeIdempotencyKey(rawIdempotencyKey);
        if (idempotencyKey != null) {
            Optional<ComplaintRecord> existing =
                repository.findByReporterAndIdempotencyKey(caller.id(), idempotencyKey);
            if (existing.isPresent()) {
                return txService.loadDetailForRecord(existing.get(), caller);
            }
        }

        try {
            return txService.createInTransaction(caller, request, idempotencyKey);
        } catch (DuplicateKeyException duplicate) {
            if (idempotencyKey != null) {
                Optional<ComplaintRecord> existing =
                    repository.findByReporterAndIdempotencyKey(caller.id(), idempotencyKey);
                if (existing.isPresent()) {
                    return txService.loadDetailForRecord(existing.get(), caller);
                }
            }
            throw duplicate;
        }
    }

    @Transactional(readOnly = true)
    public ComplaintPageResponse list(UUID callerId,
                                      String rawStatus,
                                      UUID departmentId,
                                      Boolean mine,
                                      Boolean assignedToMe,
                                      Boolean unclaimed,
                                      Boolean overdue,
                                      String q,
                                      String sort,
                                      int page,
                                      int size) {
        UserAccount caller = authService.requireActiveUser(callerId);
        int boundedPage = Math.max(0, page);
        int boundedSize = Math.min(MAX_PAGE_SIZE, Math.max(1, size));
        List<ComplaintStatus> statuses = parseStatuses(rawStatus);

        ComplaintTxService.ScopeInfo scope = txService.resolveScopeInfo(caller);
        ComplaintFilter filter = new ComplaintFilter(
            statuses, departmentId, mine, assignedToMe, unclaimed, overdue, q, sort);

        ComplaintRepository.PagedResult paged = repository.findPaged(
            caller, scope.path(), scope.type(), filter, boundedPage, boundedSize);

        List<ComplaintSummaryResponse> items = paged.items().stream()
            .map(record -> mapper.toSummary(record, caller))
            .toList();
        int totalPages = boundedSize == 0
            ? 0
            : (int) ((paged.totalElements() + boundedSize - 1) / boundedSize);

        return new ComplaintPageResponse(items, boundedPage, boundedSize, paged.totalElements(), totalPages);
    }

    @Transactional(readOnly = true)
    public SimilarComplaintsResponse findSimilar(UUID callerId, UUID locationId, UUID categoryId) {
        authService.requireActiveUser(callerId);
        Map<String, Long> byStatus = repository.countSimilarOpenByStatus(locationId, categoryId);
        long total = byStatus.values().stream().mapToLong(Long::longValue).sum();
        String mostCommon = byStatus.isEmpty() ? null : byStatus.keySet().iterator().next();
        return new SimilarComplaintsResponse(total, mostCommon, byStatus);
    }

    @Transactional(readOnly = true)
    public ComplaintDetailResponse getById(UUID callerId, UUID complaintId) {
        UserAccount caller = authService.requireActiveUser(callerId);
        ComplaintRecord record = repository.findById(complaintId)
            .orElseThrow(() -> ApiException.notFound("COMPLAINT_NOT_FOUND", "Complaint not found."));
        ComplaintTxService.ScopeInfo scope = txService.resolveScopeInfo(caller);
        if (!accessPolicy.canView(caller, record, scope.path(), scope.type())) {
            throw ApiException.forbidden("FORBIDDEN", "You do not have access to this complaint.");
        }
        return txService.loadDetailForRecord(record, caller);
    }

    @Transactional(readOnly = true)
    public void requireAttachmentAccess(UUID callerId, UUID complaintId) {
        UserAccount caller = authService.requireActiveUser(callerId);
        ComplaintRecord record = repository.findById(complaintId)
            .orElseThrow(() -> ApiException.notFound("COMPLAINT_NOT_FOUND", "Complaint not found."));
        ComplaintTxService.ScopeInfo scope = txService.resolveScopeInfo(caller);
        if (!accessPolicy.canView(caller, record, scope.path(), scope.type())) {
            throw ApiException.forbidden("FORBIDDEN", "You do not have access to this attachment.");
        }
    }

    public ComplaintDetailResponse transition(UUID callerId, UUID complaintId, TransitionRequest request) {
        UserAccount caller = authService.requireActiveUser(callerId);
        return txService.transitionInTransaction(caller, complaintId, request);
    }

    public ComplaintDetailResponse addNote(UUID callerId, UUID complaintId, AddNoteRequest request) {
        UserAccount caller = authService.requireActiveUser(callerId);
        return txService.addNoteInTransaction(caller, complaintId, request);
    }

    private static String normalizeIdempotencyKey(String raw) {
        if (raw == null || raw.isBlank()) {
            return null;
        }
        String trimmed = raw.trim();
        if (trimmed.length() > MAX_IDEMPOTENCY_KEY_LENGTH) {
            throw ApiException.badRequest("VALIDATION_FAILED",
                "Idempotency-Key must be at most " + MAX_IDEMPOTENCY_KEY_LENGTH + " characters.");
        }
        return trimmed;
    }

    private static List<ComplaintStatus> parseStatuses(String rawStatus) {
        if (rawStatus == null || rawStatus.isBlank()) {
            return List.of();
        }
        String[] parts = rawStatus.split(",");
        List<ComplaintStatus> result = new ArrayList<>(parts.length);
        for (String part : parts) {
            if (!part.isBlank()) {
                result.add(ComplaintStatus.fromString(part));
            }
        }
        return result;
    }
}
