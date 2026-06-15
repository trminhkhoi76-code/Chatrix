package com.chatrix.api.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.Size;
import lombok.Data;

@Data
public class UpdateUserRequest {

    @Size(max = 100)
    private String displayName;

    @Email
    private String email;

    private String avatarUrl;
}
