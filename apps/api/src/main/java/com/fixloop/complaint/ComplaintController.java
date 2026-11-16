package com.fixloop.complaint;

import java.util.UUID;

import com.fixloop.auth.AuthPrincipal;
import com.fixloop.complaint.dto.AddNoteRequest;
import com.fixloop.complaint.dto.ComplaintDetailResponse;
import com.fixloop.complaint.dto.ComplaintPageResponse;
import com.fixloop.complaint.dto.CreateComplaintRequest;
import com.fixloop.complaint.dto.SimilarComplaintsResponse;
import com.fixloop.complaint.dto.TransitionRequest;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** Complaint intake, queue visibility, workflow transitions and notes. */
@RestController
@RequestMapping("/api/v1/complaints")
public class ComplaintController {
    private final ComplaintService complaints;

    public ComplaintController(ComplaintService complaints) {
        this.complaints = complaints;
    }

    @PostMapping
    @PreAuthorize("hasAnyRole('STUDENT', 'ADMIN')")
    public ResponseEntity<ComplaintDetailResponse> create(
            @AuthenticationPrincipal Jwt jwt,
            @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey,
            @Valid @RequestBody CreateComplaintRequest request) {
        ComplaintDetailResponse created = complaints.create(
            AuthPrincipal.userId(jwt), request, idempotencyKey);
        return ResponseEntity.status(HttpStatus.CREATED).body(created);
    }

    @GetMapping
    public ComplaintPageResponse list(
            @AuthenticationPrincipal Jwt jwt,
            @RequestParam(required = false) String status,
            @RequestParam(required = false) UUID departmentId,
            @RequestParam(required = false) Boolean mine,
            @RequestParam(required = false) Boolean assignedToMe,
            @RequestParam(required = false) Boolean unclaimed,
            @RequestParam(required = false) Boolean overdue,
            @RequestParam(required = false) String q,
            @RequestParam(required = false) String sort,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return complaints.list(
            AuthPrincipal.userId(jwt), status, departmentId, mine, assignedToMe,
            unclaimed, overdue, q, sort, page, size);
    }

    @GetMapping("/similar")
    public SimilarComplaintsResponse similar(
            @AuthenticationPrincipal Jwt jwt,
            @RequestParam UUID locationId,
            @RequestParam UUID categoryId) {
        return complaints.findSimilar(AuthPrincipal.userId(jwt), locationId, categoryId);
    }

    @GetMapping("/{id}")
    public ComplaintDetailResponse getById(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID id) {
        return complaints.getById(AuthPrincipal.userId(jwt), id);
    }

    @PostMapping("/{id}/transition")
    public ComplaintDetailResponse transition(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID id,
            @Valid @RequestBody TransitionRequest request) {
        return complaints.transition(AuthPrincipal.userId(jwt), id, request);
    }

    @PostMapping("/{id}/notes")
    public ComplaintDetailResponse addNote(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID id,
            @Valid @RequestBody AddNoteRequest request) {
        return complaints.addNote(AuthPrincipal.userId(jwt), id, request);
    }
}
