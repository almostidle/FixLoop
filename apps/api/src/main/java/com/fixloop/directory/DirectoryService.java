package com.fixloop.directory;

import java.util.List;
import java.util.UUID;

import com.fixloop.auth.AuthService;
import com.fixloop.auth.Role;
import com.fixloop.auth.UserAccount;
import com.fixloop.common.ApiException;
import com.fixloop.directory.dto.CategoryResponse;
import com.fixloop.directory.dto.DepartmentResponse;
import com.fixloop.directory.dto.LocationResponse;
import com.fixloop.directory.dto.StaffMemberResponse;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Read-only reference directory for categories, locations, departments and staff assignment. */
@Service
@Transactional(readOnly = true)
public class DirectoryService {
    private final DirectoryRepository repository;
    private final AuthService authService;

    public DirectoryService(DirectoryRepository repository, AuthService authService) {
        this.repository = repository;
        this.authService = authService;
    }

    public List<CategoryResponse> listCategories(UUID callerId) {
        authService.requireActiveUser(callerId);
        return repository.findActiveCategories();
    }

    public List<LocationResponse> listLocations(UUID callerId, UUID parentId) {
        authService.requireActiveUser(callerId);
        return repository.findActiveLocations(parentId);
    }

    public List<DepartmentResponse> listDepartments(UUID callerId) {
        UserAccount caller = authService.requireActiveUser(callerId);
        return repository.findVisibleActiveDepartments(caller);
    }

    public List<StaffMemberResponse> listStaff(UUID callerId, UUID departmentId) {
        UserAccount caller = authService.requireActiveUser(callerId);
        if (caller.role() != Role.SUPERVISOR && caller.role() != Role.ADMIN) {
            throw ApiException.forbidden("FORBIDDEN", "Only supervisors and administrators can list staff.");
        }
        return repository.findActiveStaffUsers(caller, departmentId);
    }
}
