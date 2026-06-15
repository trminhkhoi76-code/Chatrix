package com.chatrix.api.controller;

import com.chatrix.api.dto.FileResponse;
import com.chatrix.api.service.FileService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.core.io.Resource;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.web.PageableDefault;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/files")
@RequiredArgsConstructor
@SecurityRequirement(name = "bearerAuth")
@Tag(name = "Files", description = "File upload and management")
public class FileController {

    private final FileService fileService;

    @PostMapping("/upload")
    @Operation(summary = "Upload a file")
    public ResponseEntity<FileResponse> upload(
            @RequestParam("file") MultipartFile file,
            @AuthenticationPrincipal UserDetails principal) throws IOException {
        return ResponseEntity.ok(fileService.upload(file, principal.getUsername()));
    }

    @GetMapping("/{storedName}/download")
    @Operation(summary = "Download a file by its stored name")
    public ResponseEntity<Resource> download(@PathVariable String storedName) throws IOException {
        Resource resource = fileService.download(storedName);
        return ResponseEntity.ok()
                .header(HttpHeaders.CONTENT_DISPOSITION,
                        "attachment; filename=\"" + resource.getFilename() + "\"")
                .body(resource);
    }

    @GetMapping("/mine")
    @Operation(summary = "List files uploaded by the current user")
    public ResponseEntity<Page<FileResponse>> getMyFiles(
            @AuthenticationPrincipal UserDetails principal,
            @PageableDefault(size = 20) Pageable pageable) {
        return ResponseEntity.ok(fileService.getMyFiles(principal.getUsername(), pageable));
    }

    @DeleteMapping("/{fileId}")
    @Operation(summary = "Delete an uploaded file")
    public ResponseEntity<Void> delete(
            @PathVariable UUID fileId,
            @AuthenticationPrincipal UserDetails principal) throws IOException {
        fileService.delete(fileId, principal.getUsername());
        return ResponseEntity.noContent().build();
    }
}
