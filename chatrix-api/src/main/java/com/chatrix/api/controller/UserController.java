package com.chatrix.api.controller;

import com.chatrix.api.dto.UpdateUserRequest;
import com.chatrix.api.dto.UserResponse;
import com.chatrix.api.service.UserService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.web.PageableDefault;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.web.bind.annotation.*;

import java.util.UUID;

@RestController
@RequestMapping("/api/v1/users")
@RequiredArgsConstructor
@SecurityRequirement(name = "bearerAuth")
@Tag(name = "Users", description = "User profile management")
public class UserController {

    private final UserService userService;

    @GetMapping("/me")
    @Operation(summary = "Get the current authenticated user's profile")
    public ResponseEntity<UserResponse> getMyProfile(@AuthenticationPrincipal UserDetails principal) {
        return ResponseEntity.ok(userService.getUserByUsername(principal.getUsername()));
    }

    @PutMapping("/me")
    @Operation(summary = "Update the current authenticated user's profile")
    public ResponseEntity<UserResponse> updateMyProfile(
            @AuthenticationPrincipal UserDetails principal,
            @Valid @RequestBody UpdateUserRequest request) {
        UserResponse user = userService.getUserByUsername(principal.getUsername());
        return ResponseEntity.ok(userService.updateUser(user.getId(), request));
    }

    @GetMapping("/{id}")
    @Operation(summary = "Get a user profile by ID")
    public ResponseEntity<UserResponse> getUserById(@PathVariable UUID id) {
        return ResponseEntity.ok(userService.getUserById(id));
    }

    @GetMapping
    @PreAuthorize("hasRole('ADMIN') or hasRole('MODERATOR')")
    @Operation(summary = "List all users (admin/moderator only)")
    public ResponseEntity<Page<UserResponse>> listUsers(
            @PageableDefault(size = 20) Pageable pageable) {
        return ResponseEntity.ok(userService.getAllUsers(pageable));
    }

    @DeleteMapping("/me")
    @Operation(summary = "Deactivate the current user account")
    public ResponseEntity<Void> deactivateMyAccount(@AuthenticationPrincipal UserDetails principal) {
        UserResponse user = userService.getUserByUsername(principal.getUsername());
        userService.deleteUser(user.getId());
        return ResponseEntity.noContent().build();
    }
}
