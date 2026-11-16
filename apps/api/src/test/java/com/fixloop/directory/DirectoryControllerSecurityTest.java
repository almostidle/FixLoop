package com.fixloop.directory;

import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.List;
import java.util.UUID;

import com.fixloop.auth.Role;
import com.fixloop.config.AuthConfiguration;
import com.fixloop.config.SecurityConfiguration;
import com.fixloop.directory.dto.CategoryResponse;
import com.fixloop.directory.dto.StaffMemberResponse;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(DirectoryController.class)
@Import({SecurityConfiguration.class, AuthConfiguration.class})
class DirectoryControllerSecurityTest {
    private static final UUID CALLER_ID = UUID.fromString("3f1a6c1e-1111-4a2b-9a10-0c2b7d5e4f60");

    @Autowired
    private MockMvc mvc;

    @MockitoBean
    private DirectoryService directoryService;

    @Test
    void categoriesRequireAuthentication() throws Exception {
        mvc.perform(get("/api/v1/categories"))
            .andExpect(status().isUnauthorized())
            .andExpect(jsonPath("$.code").value("UNAUTHENTICATED"));
    }

    @Test
    void signedInStudentCanListCategories() throws Exception {
        when(directoryService.listCategories(CALLER_ID))
            .thenReturn(List.of(new CategoryResponse(UUID.randomUUID(), "Plumbing", "INFRASTRUCTURE",
                "HIGH", "REQUIRED", false, 1)));

        mvc.perform(get("/api/v1/categories")
                .with(jwt().jwt(t -> t.subject(CALLER_ID.toString()).claim("role", "STUDENT"))))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$[0].name").value("Plumbing"));
    }

    @Test
    void studentsCannotAccessStaffDirectory() throws Exception {
        mvc.perform(get("/api/v1/users/staff")
                .with(jwt().jwt(t -> t.subject(CALLER_ID.toString()).claim("role", "STUDENT"))))
            .andExpect(status().isForbidden())
            .andExpect(jsonPath("$.code").value("FORBIDDEN"));
    }

    @Test
    void supervisorsCanListStaffDirectory() throws Exception {
        when(directoryService.listStaff(CALLER_ID, null))
            .thenReturn(List.of(new StaffMemberResponse(UUID.randomUUID(), "Ramesh Kumar",
                "tech.facilities@bmu.edu.in", Role.STAFF, UUID.randomUUID(), "Facilities", null)));

        mvc.perform(get("/api/v1/users/staff")
                .with(jwt().jwt(t -> t.subject(CALLER_ID.toString()).claim("role", "SUPERVISOR"))))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$[0].email").value("tech.facilities@bmu.edu.in"));
    }
}
