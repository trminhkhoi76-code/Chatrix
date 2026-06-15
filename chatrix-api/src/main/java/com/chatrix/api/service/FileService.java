package com.chatrix.api.service;

import com.chatrix.api.dto.FileResponse;
import com.chatrix.api.exception.ResourceNotFoundException;
import com.chatrix.api.model.FileMetadata;
import com.chatrix.api.model.User;
import com.chatrix.api.repository.FileMetadataRepository;
import com.chatrix.api.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.Resource;
import org.springframework.core.io.UrlResource;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.security.core.userdetails.UsernameNotFoundException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.net.MalformedURLException;
import java.nio.file.*;
import java.util.UUID;

@Service
@RequiredArgsConstructor
@Slf4j
public class FileService {

    private final FileMetadataRepository fileMetadataRepository;
    private final UserRepository userRepository;

    @Value("${chatrix.storage.upload-dir:./uploads}")
    private String uploadDir;

    @Value("${chatrix.storage.base-url:http://localhost:8080}")
    private String baseUrl;

    @Transactional
    public FileResponse upload(MultipartFile file, String username) throws IOException {
        validateFile(file);

        User uploader = userRepository.findByUsername(username)
                .orElseThrow(() -> new UsernameNotFoundException("User not found: " + username));

        String storedName = UUID.randomUUID() + "_" + file.getOriginalFilename();
        Path uploadPath = Paths.get(uploadDir).toAbsolutePath().normalize();
        Files.createDirectories(uploadPath);

        Path targetPath = uploadPath.resolve(storedName);
        Files.copy(file.getInputStream(), targetPath, StandardCopyOption.REPLACE_EXISTING);

        String publicUrl = baseUrl + "/api/v1/files/" + storedName + "/download";

        FileMetadata metadata = FileMetadata.builder()
                .originalName(file.getOriginalFilename())
                .storedName(storedName)
                .contentType(file.getContentType())
                .size(file.getSize())
                .storagePath(targetPath.toString())
                .publicUrl(publicUrl)
                .uploadedBy(uploader)
                .build();

        metadata = fileMetadataRepository.save(metadata);
        log.info("File uploaded: {} by {}", storedName, username);
        return mapToResponse(metadata);
    }

    @Transactional(readOnly = true)
    public Resource download(String storedName) throws MalformedURLException {
        Path filePath = Paths.get(uploadDir).toAbsolutePath().normalize().resolve(storedName);
        Resource resource = new UrlResource(filePath.toUri());
        if (!resource.exists() || !resource.isReadable()) {
            throw new ResourceNotFoundException("File not found: " + storedName);
        }
        return resource;
    }

    @Transactional(readOnly = true)
    public Page<FileResponse> getMyFiles(String username, Pageable pageable) {
        User user = userRepository.findByUsername(username)
                .orElseThrow(() -> new UsernameNotFoundException("User not found: " + username));
        return fileMetadataRepository.findByUploadedBy(user, pageable).map(this::mapToResponse);
    }

    @Transactional
    public void delete(UUID fileId, String username) throws IOException {
        FileMetadata metadata = fileMetadataRepository.findById(fileId)
                .orElseThrow(() -> new ResourceNotFoundException("File not found: " + fileId));

        if (!metadata.getUploadedBy().getUsername().equals(username)) {
            throw new SecurityException("Not authorized to delete this file");
        }

        Files.deleteIfExists(Paths.get(metadata.getStoragePath()));
        fileMetadataRepository.delete(metadata);
        log.info("File deleted: {} by {}", fileId, username);
    }

    private void validateFile(MultipartFile file) {
        if (file.isEmpty()) {
            throw new IllegalArgumentException("Cannot upload empty file");
        }
        long maxSizeBytes = 50 * 1024 * 1024L; // 50 MB
        if (file.getSize() > maxSizeBytes) {
            throw new IllegalArgumentException("File exceeds maximum allowed size of 50MB");
        }
    }

    private FileResponse mapToResponse(FileMetadata m) {
        return FileResponse.builder()
                .id(m.getId())
                .originalName(m.getOriginalName())
                .contentType(m.getContentType())
                .size(m.getSize())
                .publicUrl(m.getPublicUrl())
                .uploadedBy(m.getUploadedBy().getUsername())
                .uploadedAt(m.getUploadedAt())
                .build();
    }
}
