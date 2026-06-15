package com.chatrix.api.service;

import com.chatrix.api.dto.UserResponse;
import com.chatrix.api.exception.ResourceNotFoundException;
import com.chatrix.api.model.Role;
import com.chatrix.api.model.User;
import com.chatrix.api.repository.RoleRepository;
import com.chatrix.api.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.UUID;

@Service
@RequiredArgsConstructor
@Slf4j
public class AdminService {

    private final UserRepository userRepository;
    private final RoleRepository roleRepository;

    @Transactional(readOnly = true)
    public Page<UserResponse> getAllUsers(Pageable pageable) {
        return userRepository.findAll(pageable).map(this::mapToResponse);
    }

    @Transactional
    public UserResponse setUserEnabled(UUID userId, boolean enabled) {
        User user = findUser(userId);
        user.setEnabled(enabled);
        userRepository.save(user);
        log.info("Admin {} user: {}", enabled ? "enabled" : "disabled", user.getUsername());
        return mapToResponse(user);
    }

    @Transactional
    public UserResponse assignRole(UUID userId, Role.RoleName roleName) {
        User user = findUser(userId);
        Role role = roleRepository.findByName(roleName)
                .orElseThrow(() -> new ResourceNotFoundException("Role not found: " + roleName));
        user.getRoles().add(role);
        userRepository.save(user);
        log.info("Assigned role {} to user {}", roleName, user.getUsername());
        return mapToResponse(user);
    }

    @Transactional
    public UserResponse revokeRole(UUID userId, Role.RoleName roleName) {
        User user = findUser(userId);
        Role role = roleRepository.findByName(roleName)
                .orElseThrow(() -> new ResourceNotFoundException("Role not found: " + roleName));
        user.getRoles().remove(role);
        userRepository.save(user);
        log.info("Revoked role {} from user {}", roleName, user.getUsername());
        return mapToResponse(user);
    }

    @Transactional
    public void hardDeleteUser(UUID userId) {
        User user = findUser(userId);
        userRepository.delete(user);
        log.info("Admin hard-deleted user: {}", user.getUsername());
    }

    private User findUser(UUID userId) {
        return userRepository.findById(userId)
                .orElseThrow(() -> new ResourceNotFoundException("User not found: " + userId));
    }

    private UserResponse mapToResponse(User user) {
        return UserResponse.builder()
                .id(user.getId())
                .username(user.getUsername())
                .email(user.getEmail())
                .displayName(user.getDisplayName())
                .avatarUrl(user.getAvatarUrl())
                .enabled(user.isEnabled())
                .emailVerified(user.isEmailVerified())
                .roles(user.getRoles().stream().map(r -> r.getName().name()).toList())
                .createdAt(user.getCreatedAt())
                .updatedAt(user.getUpdatedAt())
                .build();
    }
}
