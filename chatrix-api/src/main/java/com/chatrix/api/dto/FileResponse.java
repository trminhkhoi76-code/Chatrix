package com.chatrix.api.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.Instant;
import java.util.UUID;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class FileResponse {

    private UUID id;
    private String originalName;
    private String contentType;
    private long size;
    private String publicUrl;
    private String uploadedBy;
    private Instant uploadedAt;
}
