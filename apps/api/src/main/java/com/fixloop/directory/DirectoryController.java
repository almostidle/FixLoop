package com.fixloop.directory;

import java.util.List;
import java.util.UUID;

import com.fixloop.auth.AuthPrincipal;
import com.fixloop.directory.dto.CategoryResponse;
import com.fixloop.directory.dto.DepartmentResponse;
import com.fixloop.directory.dto.LocationResponse;
import com.fixloop.directory.dto.StaffMemberResponse;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** Reference data endpoints for complaint intake and staff assignment. */
@RestController
@RequestMapping("/api/v1")
public class DirectoryController {
    private final DirectoryService directory;

    public DirectoryController(DirectoryService directory) {
        this.directory = directory;
    }

    @GetMapping("/categories")
    public List<CategoryResponse> categories(@AuthenticationPrincipal Jwt jwt) {
        return directory.listCategories(AuthPrincipal.userId(jwt));
    }

    @GetMapping("/locations")
    public List<LocationResponse> locations(@AuthenticationPrincipal Jwt jwt,
                                            @RequestParam(required = false) UUID parentId) {
        return directory.listLocations(AuthPrincipal.userId(jwt), parentId);
    }

    @GetMapping("/departments")
    public List<DepartmentResponse> departments(@AuthenticationPrincipal Jwt jwt) {
        return directory.listDepartments(AuthPrincipal.userId(jwt));
    }

    @GetMapping("/users/staff")
    @PreAuthorize("hasAnyRole('SUPERVISOR', 'ADMIN')")
    public List<StaffMemberResponse> staff(@AuthenticationPrincipal Jwt jwt,
                                           @RequestParam(required = false) UUID departmentId) {
        return directory.listStaff(AuthPrincipal.userId(jwt), departmentId);
    }
}
