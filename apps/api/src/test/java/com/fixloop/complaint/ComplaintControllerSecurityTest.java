package com.fixloop.complaint;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import com.fixloop.complaint.dto.ComplaintDetailResponse;
import com.fixloop.complaint.dto.ComplaintPageResponse;
import com.fixloop.config.AuthConfiguration;
import com.fixloop.config.SecurityConfiguration;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(ComplaintController.class)
@Import({SecurityConfiguration.class, AuthConfiguration.class})
class ComplaintControllerSecurityTest {
    private static final UUID CALLER_ID = UUID.fromString("3f1a6c1e-1111-4a2b-9a10-0c2b7d5e4f60");
    private static final UUID CATEGORY_ID = UUID.fromString("11111111-1111-4111-8111-111111111111");
    private static final UUID LOCATION_ID = UUID.fromString("22222222-2222-4222-8222-222222222222");

    @Autowired
    private MockMvc mvc;

    @MockitoBean
    private ComplaintService complaintService;

    @Test
    void unauthenticatedRequestsReturn401() throws Exception {
        mvc.perform(get("/api/v1/complaints"))
            .andExpect(status().isUnauthorized())
            .andExpect(jsonPath("$.code").value("UNAUTHENTICATED"));
    }

    @Test
    void staffCannotSubmitComplaints() throws Exception {
        mvc.perform(post("/api/v1/complaints")
                .with(jwt().jwt(t -> t.subject(CALLER_ID.toString()).claim("role", "STAFF"))
                    .authorities(new SimpleGrantedAuthority("ROLE_STAFF")))
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {"categoryId":"%s","locationId":"%s","title":"Broken hallway light"}
                    """.formatted(CATEGORY_ID, LOCATION_ID)))
            .andExpect(status().isForbidden())
            .andExpect(jsonPath("$.code").value("FORBIDDEN"));
    }

    @Test
    void studentCanSubmitComplaintAndReadFeed() throws Exception {
        ComplaintDetailResponse created = new ComplaintDetailResponse(
            UUID.randomUUID(), "FL-2026-000027", "Broken hallway light", null, "MEDIUM", "ASSIGNED",
            CATEGORY_ID, "Electrical", "INFRASTRUCTURE", false, "OPTIONAL",
            LOCATION_ID, "Floor 2", "/bmu/boys-hostel-t1/floor-2",
            UUID.randomUUID(), "Facilities", "FAC", null, null,
            Instant.now().plusSeconds(3600), 0, 0, 1, true, null,
            Instant.now(), Instant.now(), null, null, List.of(), List.of());

        when(complaintService.create(eq(CALLER_ID), any(), eq("idem-1"))).thenReturn(created);
        when(complaintService.list(eq(CALLER_ID), any(), any(), any(), any(), any(), any(), any(), any(), eq(0), eq(20)))
            .thenReturn(new ComplaintPageResponse(List.of(), 0, 20, 0, 0));

        mvc.perform(post("/api/v1/complaints")
                .with(jwt().jwt(t -> t.subject(CALLER_ID.toString()).claim("role", "STUDENT"))
                    .authorities(new SimpleGrantedAuthority("ROLE_STUDENT")))
                .header("Idempotency-Key", "idem-1")
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {"categoryId":"%s","locationId":"%s","title":"Broken hallway light"}
                    """.formatted(CATEGORY_ID, LOCATION_ID)))
            .andExpect(status().isCreated())
            .andExpect(jsonPath("$.code").value("FL-2026-000027"));

        mvc.perform(get("/api/v1/complaints")
                .with(jwt().jwt(t -> t.subject(CALLER_ID.toString()).claim("role", "STUDENT"))
                    .authorities(new SimpleGrantedAuthority("ROLE_STUDENT"))))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.page").value(0));
    }

    @Test
    void rejectsShortTitleWithValidationError() throws Exception {
        mvc.perform(post("/api/v1/complaints")
                .with(jwt().jwt(t -> t.subject(CALLER_ID.toString()).claim("role", "STUDENT"))
                    .authorities(new SimpleGrantedAuthority("ROLE_STUDENT")))
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {"categoryId":"%s","locationId":"%s","title":"No"}
                    """.formatted(CATEGORY_ID, LOCATION_ID)))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("VALIDATION_FAILED"))
            .andExpect(jsonPath("$.details.title").exists());
    }
}
