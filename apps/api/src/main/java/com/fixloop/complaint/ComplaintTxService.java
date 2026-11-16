package com.fixloop.complaint;

import java.time.Clock;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import com.fixloop.auth.Role;
import com.fixloop.auth.UserAccount;
import com.fixloop.auth.UserRepository;
import com.fixloop.common.ApiException;
import com.fixloop.complaint.dto.AddNoteRequest;
import com.fixloop.complaint.dto.ComplaintDetailResponse;
import com.fixloop.complaint.dto.CreateComplaintRequest;
import com.fixloop.complaint.dto.TransitionRequest;
import com.fixloop.directory.DirectoryRepository;
import com.fixloop.directory.dto.CategoryResponse;
import com.fixloop.directory.dto.DepartmentResponse;
import com.fixloop.directory.dto.LocationResponse;
import com.fixloop.notification.NotificationService;
import com.fixloop.storage.AttachmentLinkService;
import com.fixloop.storage.AttachmentLinkService.ValidatedAttachment;
import com.fixloop.storage.AttachmentRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Runs complaint mutations inside explicit transactions so optimistic lock checks,
 * append-only events, attachment linking, and in-app notifications commit atomically.
 */
@Service
public class ComplaintTxService {
    private static final String VERSION_CONFLICT_MESSAGE =
        "This complaint was updated by someone else. Refresh and try again.";

    private final ComplaintRepository repository;
    private final DirectoryRepository directory;
    private final UserRepository users;
    private final RoutingService routingService;
    private final SlaService slaService;
    private final ComplaintAccessPolicy accessPolicy;
    private final ComplaintMapper mapper;
    private final AttachmentRepository attachments;
    private final AttachmentLinkService attachmentLinks;
    private final NotificationService notifications;
    private final Clock clock;

    public ComplaintTxService(ComplaintRepository repository,
                              DirectoryRepository directory,
                              UserRepository users,
                              RoutingService routingService,
                              SlaService slaService,
                              ComplaintAccessPolicy accessPolicy,
                              ComplaintMapper mapper,
                              AttachmentRepository attachments,
                              AttachmentLinkService attachmentLinks,
                              NotificationService notifications,
                              Clock clock) {
        this.repository = repository;
        this.directory = directory;
        this.users = users;
        this.routingService = routingService;
        this.slaService = slaService;
        this.accessPolicy = accessPolicy;
        this.mapper = mapper;
        this.attachments = attachments;
        this.attachmentLinks = attachmentLinks;
        this.notifications = notifications;
        this.clock = clock;
    }

    @Transactional
    public ComplaintDetailResponse createInTransaction(UserAccount caller,
                                                       CreateComplaintRequest request,
                                                       String idempotencyKey) {
        if (idempotencyKey != null) {
            Optional<ComplaintRecord> existing =
                repository.findByReporterAndIdempotencyKey(caller.id(), idempotencyKey);
            if (existing.isPresent()) {
                return loadDetailForRecord(existing.get(), caller);
            }
        }

        CategoryResponse category = directory.findActiveCategoryById(request.categoryId())
            .orElseThrow(() -> ApiException.unprocessable("INVALID_CATEGORY",
                "Selected category does not exist or is inactive."));
        LocationResponse location = directory.findActiveLocationById(request.locationId())
            .orElseThrow(() -> ApiException.unprocessable("INVALID_LOCATION",
                "Selected location does not exist or is inactive."));

        ComplaintSeverity severity = (request.severity() == null || request.severity().isBlank())
            ? ComplaintSeverity.fromString(category.defaultSeverity())
            : ComplaintSeverity.fromString(request.severity());

        List<ValidatedAttachment> validatedPhotos =
            attachmentLinks.validateForComplaint(request.attachmentKeys());
        enforcePhotoPolicy(category.photoPolicy(), validatedPhotos);

        ComplaintRepository.TransitionRuleRecord createRule = repository.findTransitionRule(null, "REPORTED")
            .orElseThrow(() -> new IllegalStateException("Missing initial status transition rule"));
        if (!createRule.allowedRoles().contains(caller.role().name())) {
            throw ApiException.forbidden("FORBIDDEN", "Your role cannot create complaints.");
        }

        String title = request.title().trim();
        String description = request.description() == null ? null : request.description().trim();
        if (description != null && description.isEmpty()) {
            description = null;
        }

        String code = repository.nextComplaintCode();
        UUID complaintId = repository.insertComplaint(
            code, caller.id(), category.id(), location.id(), title, description,
            severity.name(), idempotencyKey);

        Map<String, Object> createdPayload = new LinkedHashMap<>();
        createdPayload.put("code", code);
        createdPayload.put("severity", severity.name());
        repository.insertEvent(complaintId, caller.id(), caller.role().name(),
            "CREATED", null, "REPORTED", createdPayload);

        attachmentLinks.linkAll(complaintId, null, "REPORT", validatedPhotos);

        Instant now = clock.instant();
        Instant slaDueAt = slaService.computeDueAt(category.id(), severity, now);

        Optional<RoutingService.RoutingDecision> decisionOpt = routingService.match(
            repository.findActiveRoutingRules(),
            category.id(),
            category.isSensitive(),
            location.path(),
            severity);

        if (decisionOpt.isPresent()) {
            RoutingService.RoutingDecision decision = decisionOpt.get();
            RoutingRuleRecord rule = decision.rule();

            repository.updateInitialRoutingAndSla(
                complaintId, "ASSIGNED", rule.departmentId(), slaDueAt, true);

            Map<String, Object> routePayload = new LinkedHashMap<>();
            routePayload.put("department", rule.departmentCode());
            routePayload.put("rule_id", rule.id().toString());
            repository.insertEvent(
                complaintId,
                null,
                "SYSTEM",
                decision.fallback() ? "ROUTING_FALLBACK" : "ROUTED",
                "REPORTED",
                "ASSIGNED",
                routePayload);

            DepartmentResponse dept = directory.findActiveDepartmentById(rule.departmentId()).orElse(null);
            if (dept != null && dept.headUserId() != null && !dept.headUserId().equals(caller.id())) {
                notifications.queueInApp(dept.headUserId(), "COMPLAINT_ASSIGNED", notificationPayload(
                    complaintId, code,
                    "New issue " + code + " (" + title + ") routed to " + dept.name() + "."));
            }
            notifications.queueInApp(caller.id(), "COMPLAINT_SUBMITTED", notificationPayload(
                complaintId, code,
                "Issue " + code + " submitted and routed to " + rule.departmentName() + "."));
        } else {
            repository.updateInitialRoutingAndSla(complaintId, "REPORTED", null, slaDueAt, false);
            notifications.queueInApp(caller.id(), "COMPLAINT_SUBMITTED", notificationPayload(
                complaintId, code,
                "Issue " + code + " submitted and awaiting triage."));
        }

        ComplaintRecord created = repository.findById(complaintId)
            .orElseThrow(() -> new IllegalStateException("Created complaint not found"));
        return loadDetailForRecord(created, caller);
    }

    @Transactional
    public ComplaintDetailResponse transitionInTransaction(UserAccount caller,
                                                           UUID complaintId,
                                                           TransitionRequest request) {
        ComplaintRecord complaint = repository.findById(complaintId)
            .orElseThrow(() -> ApiException.notFound("COMPLAINT_NOT_FOUND",
                "Complaint not found."));

        ScopeInfo callerScope = resolveScopeInfo(caller);
        if (!accessPolicy.canView(caller, complaint, callerScope.path(), callerScope.type())) {
            throw ApiException.forbidden("FORBIDDEN", "You do not have access to this complaint.");
        }

        ComplaintStatus fromStatus = ComplaintStatus.fromString(complaint.status());
        ComplaintStatus toStatus = ComplaintStatus.fromString(request.toStatus());

        if (complaint.version() != request.version()) {
            throw ApiException.conflict("VERSION_CONFLICT", VERSION_CONFLICT_MESSAGE);
        }

        ComplaintRepository.TransitionRuleRecord rule = repository
            .findTransitionRule(fromStatus.name(), toStatus.name())
            .orElseThrow(() -> ApiException.unprocessable("INVALID_TRANSITION",
                "Cannot transition complaint from " + fromStatus.name() + " to " + toStatus.name() + "."));

        if (rule.systemOnly()) {
            throw ApiException.forbidden("SYSTEM_ONLY_TRANSITION",
                "This transition is handled automatically by the system.");
        }
        if (!rule.allowedRoles().contains(caller.role().name())) {
            throw ApiException.forbidden("FORBIDDEN",
                "Your role cannot move this complaint from " + fromStatus.name() + " to " + toStatus.name() + ".");
        }

        String note = request.note() == null ? "" : request.note().trim();
        if (rule.requiresNote() && note.isEmpty()) {
            throw ApiException.badRequest("NOTE_REQUIRED",
                "Please add a note explaining this status update.");
        }

        if (fromStatus == ComplaintStatus.REPORTED && toStatus == ComplaintStatus.ASSIGNED) {
            handleManualRoute(caller, complaint, request, note);
        } else if (fromStatus == ComplaintStatus.REPORTED && toStatus == ComplaintStatus.REJECTED) {
            handleReject(caller, complaint, note);
        } else if (fromStatus == ComplaintStatus.ASSIGNED && toStatus == ComplaintStatus.ASSIGNED) {
            handleReassign(caller, complaint, request, note);
        } else if (fromStatus == ComplaintStatus.ASSIGNED && toStatus == ComplaintStatus.IN_PROGRESS) {
            handleClaim(caller, complaint, note);
        } else if (fromStatus == ComplaintStatus.IN_PROGRESS && toStatus == ComplaintStatus.ASSIGNED) {
            handleRelease(caller, complaint, note);
        } else if (fromStatus == ComplaintStatus.IN_PROGRESS && toStatus == ComplaintStatus.RESOLVED) {
            handleResolve(caller, complaint, request, note);
        } else if (fromStatus == ComplaintStatus.RESOLVED && toStatus == ComplaintStatus.VERIFIED) {
            handleVerify(caller, complaint, note);
        } else if (fromStatus == ComplaintStatus.RESOLVED && toStatus == ComplaintStatus.REOPENED) {
            handleReopen(caller, complaint, note);
        } else {
            throw ApiException.unprocessable("INVALID_TRANSITION",
                "Cannot transition complaint from " + fromStatus.name() + " to " + toStatus.name() + ".");
        }

        ComplaintRecord updated = repository.findById(complaintId)
            .orElseThrow(() -> new IllegalStateException("Updated complaint not found"));
        return loadDetailForRecord(updated, caller);
    }

    @Transactional
    public ComplaintDetailResponse addNoteInTransaction(UserAccount caller,
                                                        UUID complaintId,
                                                        AddNoteRequest request) {
        ComplaintRecord complaint = repository.findById(complaintId)
            .orElseThrow(() -> ApiException.notFound("COMPLAINT_NOT_FOUND",
                "Complaint not found."));

        ScopeInfo callerScope = resolveScopeInfo(caller);
        if (!accessPolicy.canPostNote(caller, complaint, callerScope.path(), callerScope.type())) {
            throw ApiException.forbidden("FORBIDDEN",
                "You are not authorized to add notes to this complaint.");
        }

        String note = request.note().trim();
        Map<String, Object> payload = Map.of("note", note);
        repository.insertEvent(
            complaintId, caller.id(), caller.role().name(),
            "NOTE", complaint.status(), complaint.status(), payload);
        repository.touchUpdatedAt(complaintId);

        if (caller.id().equals(complaint.reporterId())) {
            UUID staffTarget = complaint.assignedTo() != null
                ? complaint.assignedTo()
                : complaint.departmentHeadUserId();
            if (staffTarget != null && !staffTarget.equals(caller.id())) {
                notifications.queueInApp(staffTarget, "COMPLAINT_NOTE", notificationPayload(
                    complaint.id(), complaint.code(),
                    "Reporter added a note on " + complaint.code() + ": " + preview(note)));
            }
        } else if (!complaint.reporterId().equals(caller.id())) {
            notifications.queueInApp(complaint.reporterId(), "COMPLAINT_NOTE", notificationPayload(
                complaint.id(), complaint.code(),
                "Update on " + complaint.code() + ": " + preview(note)));
        }

        ComplaintRecord updated = repository.findById(complaintId)
            .orElseThrow(() -> new IllegalStateException("Complaint not found"));
        return loadDetailForRecord(updated, caller);
    }

    public ComplaintDetailResponse loadDetailForRecord(ComplaintRecord record, UserAccount caller) {
        return mapper.toDetail(
            record,
            caller,
            repository.findEventsForComplaint(record.id()),
            attachments.findByComplaintId(record.id()));
    }

    public ScopeInfo resolveScopeInfo(UserAccount user) {
        if (user.scopeLocationId() == null) {
            return new ScopeInfo(null, null);
        }
        return directory.findLocationById(user.scopeLocationId())
            .map(loc -> new ScopeInfo(loc.path(), loc.type()))
            .orElse(new ScopeInfo(null, null));
    }

    private void handleManualRoute(UserAccount caller, ComplaintRecord complaint,
                                   TransitionRequest request, String note) {
        if (request.departmentId() == null) {
            throw ApiException.badRequest("DEPARTMENT_REQUIRED",
                "A target department is required when routing a complaint.");
        }
        DepartmentResponse dept = requireAssignableDepartment(complaint, request.departmentId());
        UserAccount assignee = validateAssignee(request.assignedTo(), dept.id());

        Instant slaDueAt = complaint.slaDueAt();
        if (slaDueAt == null) {
            slaDueAt = slaService.computeDueAt(
                complaint.categoryId(),
                ComplaintSeverity.fromString(complaint.severity()),
                clock.instant());
        }

        int rows = repository.applyRouteFromReported(
            complaint.id(), complaint.version(), dept.id(),
            assignee == null ? null : assignee.id(), slaDueAt);
        if (rows == 0) {
            throw ApiException.conflict("VERSION_CONFLICT", VERSION_CONFLICT_MESSAGE);
        }

        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("department", dept.code());
        if (assignee != null) {
            payload.put("assigned_to", assignee.id().toString());
            payload.put("assignee", assignee.fullName());
        }
        if (!note.isEmpty()) {
            payload.put("note", note);
        }
        repository.insertEvent(complaint.id(), caller.id(), caller.role().name(),
            "ROUTED", "REPORTED", "ASSIGNED", payload);

        UUID notifyTarget = assignee != null ? assignee.id() : dept.headUserId();
        if (notifyTarget != null && !notifyTarget.equals(caller.id())) {
            notifications.queueInApp(notifyTarget, "COMPLAINT_ASSIGNED", notificationPayload(
                complaint.id(), complaint.code(),
                "Issue " + complaint.code() + " (" + complaint.title() + ") was assigned to " + dept.name() + "."));
        }
        if (!complaint.reporterId().equals(caller.id())) {
            notifications.queueInApp(complaint.reporterId(), "COMPLAINT_ASSIGNED", notificationPayload(
                complaint.id(), complaint.code(),
                "Issue " + complaint.code() + " was routed to " + dept.name() + "."));
        }
    }

    private void handleReject(UserAccount caller, ComplaintRecord complaint, String note) {
        int rows = repository.applyReject(complaint.id(), complaint.version());
        if (rows == 0) {
            throw ApiException.conflict("VERSION_CONFLICT", VERSION_CONFLICT_MESSAGE);
        }
        repository.insertEvent(complaint.id(), caller.id(), caller.role().name(),
            "REJECTED", "REPORTED", "REJECTED", Map.of("note", note));

        if (!complaint.reporterId().equals(caller.id())) {
            notifications.queueInApp(complaint.reporterId(), "COMPLAINT_REJECTED", notificationPayload(
                complaint.id(), complaint.code(),
                "Issue " + complaint.code() + " was closed as rejected: " + preview(note)));
        }
    }

    private void handleReassign(UserAccount caller, ComplaintRecord complaint,
                                TransitionRequest request, String note) {
        UUID targetDepartmentId = request.departmentId() != null
            ? request.departmentId()
            : complaint.departmentId();
        if (targetDepartmentId == null) {
            throw ApiException.badRequest("DEPARTMENT_REQUIRED",
                "A target department is required when reassigning a complaint.");
        }
        DepartmentResponse dept = requireAssignableDepartment(complaint, targetDepartmentId);
        UserAccount assignee = validateAssignee(request.assignedTo(), dept.id());

        int rows = repository.applyReassign(
            complaint.id(), complaint.version(), dept.id(),
            assignee == null ? null : assignee.id());
        if (rows == 0) {
            throw ApiException.conflict("VERSION_CONFLICT", VERSION_CONFLICT_MESSAGE);
        }

        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("department", dept.code());
        if (assignee != null) {
            payload.put("assigned_to", assignee.id().toString());
            payload.put("assignee", assignee.fullName());
        }
        payload.put("note", note);
        repository.insertEvent(complaint.id(), caller.id(), caller.role().name(),
            "REASSIGNED", "ASSIGNED", "ASSIGNED", payload);

        UUID targetUser = assignee != null ? assignee.id() : dept.headUserId();
        if (targetUser != null && !targetUser.equals(caller.id())) {
            notifications.queueInApp(targetUser, "COMPLAINT_ASSIGNED", notificationPayload(
                complaint.id(), complaint.code(),
                "Issue " + complaint.code() + " (" + complaint.title() + ") was reassigned to "
                    + (assignee != null ? assignee.fullName() : dept.name()) + "."));
        }
    }

    private void handleClaim(UserAccount caller, ComplaintRecord complaint, String note) {
        if (complaint.assignedTo() != null && !complaint.assignedTo().equals(caller.id())) {
            throw ApiException.conflict("ALREADY_CLAIMED",
                "This issue is already assigned to "
                    + (complaint.assigneeName() == null ? "another team member" : complaint.assigneeName()) + ".");
        }
        int rows = repository.applyClaim(complaint.id(), complaint.version(), caller.id());
        if (rows == 0) {
            throw ApiException.conflict("ALREADY_CLAIMED",
                "Someone else claimed or updated this issue. Refresh and try again.");
        }
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("assignee", caller.fullName());
        if (!note.isEmpty()) {
            payload.put("note", note);
        }
        repository.insertEvent(complaint.id(), caller.id(), caller.role().name(),
            "CLAIMED", "ASSIGNED", "IN_PROGRESS", payload);

        if (!complaint.reporterId().equals(caller.id())) {
            notifications.queueInApp(complaint.reporterId(), "COMPLAINT_IN_PROGRESS", notificationPayload(
                complaint.id(), complaint.code(),
                "Work started on " + complaint.code() + " (" + complaint.title() + ")."));
        }
    }

    private void handleRelease(UserAccount caller, ComplaintRecord complaint, String note) {
        if (caller.role() == Role.STAFF && !caller.id().equals(complaint.assignedTo())) {
            throw ApiException.forbidden("FORBIDDEN",
                "Only the assigned staff member or a supervisor can release this issue.");
        }
        int rows = repository.applyRelease(complaint.id(), complaint.version());
        if (rows == 0) {
            throw ApiException.conflict("VERSION_CONFLICT", VERSION_CONFLICT_MESSAGE);
        }
        repository.insertEvent(complaint.id(), caller.id(), caller.role().name(),
            "RELEASED", "IN_PROGRESS", "ASSIGNED", Map.of("note", note));

        if (complaint.departmentHeadUserId() != null && !complaint.departmentHeadUserId().equals(caller.id())) {
            notifications.queueInApp(complaint.departmentHeadUserId(), "COMPLAINT_RELEASED", notificationPayload(
                complaint.id(), complaint.code(),
                "Issue " + complaint.code() + " was released back to the " + complaint.departmentName() + " queue."));
        }
    }

    private void handleResolve(UserAccount caller, ComplaintRecord complaint,
                               TransitionRequest request, String note) {
        if (caller.role() == Role.STAFF && !caller.id().equals(complaint.assignedTo())) {
            throw ApiException.forbidden("FORBIDDEN",
                "Only the assigned staff member or a supervisor can resolve this issue.");
        }

        List<ValidatedAttachment> validatedPhotos =
            attachmentLinks.validateForComplaint(request.attachmentKeys());
        if ("DISABLED".equals(complaint.categoryPhotoPolicy()) && !validatedPhotos.isEmpty()) {
            throw ApiException.unprocessable("PHOTO_NOT_ALLOWED",
                "Photographs are disabled for this category.");
        }

        int rows = repository.applyResolve(complaint.id(), complaint.version());
        if (rows == 0) {
            throw ApiException.conflict("VERSION_CONFLICT", VERSION_CONFLICT_MESSAGE);
        }

        Long eventId = repository.insertEvent(
            complaint.id(), caller.id(), caller.role().name(),
            "RESOLVED", "IN_PROGRESS", "RESOLVED", Map.of("note", note));

        attachmentLinks.linkAll(complaint.id(), eventId, "RESOLUTION", validatedPhotos);

        if (!complaint.reporterId().equals(caller.id())) {
            notifications.queueInApp(complaint.reporterId(), "COMPLAINT_RESOLVED", notificationPayload(
                complaint.id(), complaint.code(),
                "Issue " + complaint.code() + " was marked resolved. Please verify the fix."));
        }
    }

    private void handleVerify(UserAccount caller, ComplaintRecord complaint, String note) {
        if (!complaint.reporterId().equals(caller.id())) {
            throw ApiException.forbidden("NOT_YOUR_COMPLAINT",
                "Only the student who reported this issue can verify the fix.");
        }
        int rows = repository.applyVerify(complaint.id(), complaint.version());
        if (rows == 0) {
            throw ApiException.conflict("VERSION_CONFLICT", VERSION_CONFLICT_MESSAGE);
        }
        Map<String, Object> payload = note.isEmpty() ? Map.of() : Map.of("note", note);
        repository.insertEvent(complaint.id(), caller.id(), caller.role().name(),
            "VERIFIED", "RESOLVED", "VERIFIED", payload);

        UUID notifyTarget = complaint.assignedTo() != null
            ? complaint.assignedTo()
            : complaint.departmentHeadUserId();
        if (notifyTarget != null && !notifyTarget.equals(caller.id())) {
            notifications.queueInApp(notifyTarget, "COMPLAINT_VERIFIED", notificationPayload(
                complaint.id(), complaint.code(),
                "Fix for " + complaint.code() + " was verified and closed by the reporter."));
        }
    }

    private void handleReopen(UserAccount caller, ComplaintRecord complaint, String note) {
        if (!complaint.reporterId().equals(caller.id())) {
            throw ApiException.forbidden("NOT_YOUR_COMPLAINT",
                "Only the student who reported this issue can reopen it.");
        }
        int rows = repository.applyReopen(complaint.id(), complaint.version());
        if (rows == 0) {
            throw ApiException.conflict("VERSION_CONFLICT", VERSION_CONFLICT_MESSAGE);
        }

        int newReopenCount = complaint.reopenCount() + 1;
        Map<String, Object> reopenPayload = new LinkedHashMap<>();
        reopenPayload.put("note", note);
        reopenPayload.put("reopen_count", newReopenCount);
        repository.insertEvent(complaint.id(), caller.id(), caller.role().name(),
            "REOPENED", "RESOLVED", "REOPENED", reopenPayload);

        // Immediately apply the REOPENED -> ASSIGNED system auto-route transition if configured.
        UUID routedDepartmentId = complaint.departmentId();
        String routedDepartmentCode = complaint.departmentCode();
        UUID routedHeadId = complaint.departmentHeadUserId();
        Optional<ComplaintRepository.TransitionRuleRecord> systemReassign =
            repository.findTransitionRule("REOPENED", "ASSIGNED");

        if (systemReassign.isPresent() && systemReassign.get().allowedRoles().contains("SYSTEM")) {
            ComplaintSeverity severity = ComplaintSeverity.fromString(complaint.severity());
            Optional<RoutingService.RoutingDecision> decisionOpt = routingService.match(
                repository.findActiveRoutingRules(),
                complaint.categoryId(),
                complaint.categoryIsSensitive(),
                complaint.locationPath(),
                severity);

            boolean fallback = false;
            UUID ruleId = null;
            if (decisionOpt.isPresent()) {
                RoutingRuleRecord rule = decisionOpt.get().rule();
                routedDepartmentId = rule.departmentId();
                routedDepartmentCode = rule.departmentCode();
                fallback = decisionOpt.get().fallback();
                ruleId = rule.id();
                routedHeadId = directory.findActiveDepartmentById(routedDepartmentId)
                    .map(DepartmentResponse::headUserId)
                    .orElse(routedHeadId);
            }

            if (routedDepartmentId != null) {
                Instant newSlaDue = slaService.computeDueAt(
                    complaint.categoryId(), severity, clock.instant());
                int routedRows = repository.applySystemRouteFromReopened(
                    complaint.id(), routedDepartmentId, newSlaDue);
                if (routedRows > 0) {
                    Map<String, Object> routePayload = new LinkedHashMap<>();
                    routePayload.put("department", routedDepartmentCode);
                    if (ruleId != null) {
                        routePayload.put("rule_id", ruleId.toString());
                    }
                    repository.insertEvent(
                        complaint.id(),
                        null,
                        "SYSTEM",
                        fallback ? "ROUTING_FALLBACK" : "ROUTED",
                        "REOPENED",
                        "ASSIGNED",
                        routePayload);
                }
            }
        }

        if (complaint.assignedTo() != null && !complaint.assignedTo().equals(caller.id())) {
            notifications.queueInApp(complaint.assignedTo(), "COMPLAINT_REOPENED", notificationPayload(
                complaint.id(), complaint.code(),
                "Issue " + complaint.code() + " was reopened by the reporter: " + preview(note)));
        }
        if (routedHeadId != null
                && !routedHeadId.equals(caller.id())
                && !routedHeadId.equals(complaint.assignedTo())) {
            notifications.queueInApp(routedHeadId, "COMPLAINT_REOPENED", notificationPayload(
                complaint.id(), complaint.code(),
                "Issue " + complaint.code() + " was reopened and returned to your queue."));
        }
    }

    private DepartmentResponse requireAssignableDepartment(ComplaintRecord complaint, UUID departmentId) {
        DepartmentResponse dept = directory.findActiveDepartmentById(departmentId)
            .orElseThrow(() -> ApiException.unprocessable("INVALID_DEPARTMENT",
                "Selected department does not exist or is inactive."));
        if (complaint.categoryIsSensitive() && !"RESTRICTED".equals(dept.kind())) {
            throw ApiException.unprocessable("SENSITIVE_DEPARTMENT_REQUIRED",
                "Sensitive complaints may only be assigned to a restricted department.");
        }
        return dept;
    }

    private UserAccount validateAssignee(UUID assignedTo, UUID departmentId) {
        if (assignedTo == null) {
            return null;
        }
        UserAccount user = users.findById(assignedTo)
            .filter(UserAccount::active)
            .orElseThrow(() -> ApiException.unprocessable("INVALID_ASSIGNEE",
                "Selected staff member does not exist or is inactive."));
        if (user.role() != Role.STAFF && user.role() != Role.SUPERVISOR) {
            throw ApiException.unprocessable("INVALID_ASSIGNEE",
                "Only staff members or supervisors can be assigned to a complaint.");
        }
        if (!departmentId.equals(user.departmentId())) {
            throw ApiException.unprocessable("ASSIGNEE_DEPARTMENT_MISMATCH",
                "Selected staff member does not belong to the target department.");
        }
        return user;
    }

    private static void enforcePhotoPolicy(String photoPolicy, List<ValidatedAttachment> photos) {
        if ("DISABLED".equals(photoPolicy) && !photos.isEmpty()) {
            throw ApiException.unprocessable("PHOTO_NOT_ALLOWED",
                "Photographs are disabled for this category.");
        }
        if ("REQUIRED".equals(photoPolicy) && photos.isEmpty()) {
            throw ApiException.unprocessable("PHOTO_REQUIRED",
                "This category requires at least one photograph.");
        }
    }

    private static Map<String, Object> notificationPayload(UUID complaintId, String code, String message) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("complaint_id", complaintId.toString());
        payload.put("code", code);
        payload.put("message", message);
        return payload;
    }

    private static String preview(String note) {
        return note.length() <= 80 ? note : note.substring(0, 77) + "...";
    }

    public record ScopeInfo(String path, String type) {
    }
}
