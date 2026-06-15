package com.chatrix.api.controller;

import com.chatrix.api.dto.UserResponse;
import com.chatrix.api.model.Role;
import com.chatrix.api.service.AdminService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.web.PageableDefault;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.util.UUID;

@RestController
@RequestMapping("/api/v1/admin")
@RequiredArgsConstructor
@PreAuthorize("hasRole('ADMIN')")
@SecurityRequirement(name = "bearerAuth")
@Tag(name = "Admin", description = "Administrative operations")
public class AdminController {

    private final AdminService adminService;

    @GetMapping("/users")
    @Operation(summary = "List all users with pagination")
    public ResponseEntity<Page<UserResponse>> listUsers(@PageableDefault(size = 20) Pageable pageable) {
        return ResponseEntity.ok(adminService.getAllUsers(pageable));
    }

    @PatchMapping("/users/{userId}/enable")
    @Operation(summary = "Enable a user account")
    public ResponseEntity<UserResponse> enableUser(@PathVariable UUID userId) {
        return ResponseEntity.ok(adminService.setUserEnabled(userId, true));
    }

    @PatchMapping("/users/{userId}/disable")
    @Operation(summary = "Disable a user account")
    public ResponseEntity<UserResponse> disableUser(@PathVariable UUID userId) {
        return ResponseEntity.ok(adminService.setUserEnabled(userId, false));
    }

    @PostMapping("/users/{userId}/roles/{roleName}")
    @Operation(summary = "Assign a role to a user")
    public ResponseEntity<UserResponse> assignRole(
            @PathVariable UUID userId,
            @PathVariable Role.RoleName roleName) {
        return ResponseEntity.ok(adminService.assignRole(userId, roleName));
    }

    @DeleteMapping("/users/{userId}/roles/{roleName}")
    @Operation(summary = "Revoke a role from a user")
    public ResponseEntity<UserResponse> revokeRole(
            @PathVariable UUID userId,
            @PathVariable Role.RoleName roleName) {
        return ResponseEntity.ok(adminService.revokeRole(userId, roleName));
    }

    @DeleteMapping("/users/{userId}")
    @Operation(summary = "Permanently delete a user (hard delete)")
    public ResponseEntity<Void> hardDeleteUser(@PathVariable UUID userId) {
        adminService.hardDeleteUser(userId);
        return ResponseEntity.noContent().build();
    }
}
