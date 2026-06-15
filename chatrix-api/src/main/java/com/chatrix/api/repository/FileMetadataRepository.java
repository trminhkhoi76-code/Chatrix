package com.chatrix.api.repository;

import com.chatrix.api.model.FileMetadata;
import com.chatrix.api.model.User;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.UUID;

@Repository
public interface FileMetadataRepository extends JpaRepository<FileMetadata, UUID> {

    Page<FileMetadata> findByUploadedBy(User user, Pageable pageable);
}
