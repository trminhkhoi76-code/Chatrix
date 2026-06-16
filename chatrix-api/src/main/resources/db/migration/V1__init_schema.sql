-- V1__init_schema.sql
-- Initial schema for Chatrix (MySQL 8.0+)

CREATE TABLE roles (
    id          BINARY(16) PRIMARY KEY,
    name        ENUM('ROLE_USER','ROLE_MODERATOR','ROLE_ADMIN') NOT NULL UNIQUE
);

CREATE TABLE users (
    id             BINARY(16) PRIMARY KEY,
    username       VARCHAR(50)  NOT NULL UNIQUE,
    email          VARCHAR(255) NOT NULL UNIQUE,
    password       VARCHAR(255) NOT NULL,
    display_name   VARCHAR(100),
    avatar_url     VARCHAR(500),
    enabled        BIT(1) NOT NULL DEFAULT 1,
    email_verified BIT(1) NOT NULL DEFAULT 0,
    created_at     DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at     DATETIME(6) NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP(6)
);

CREATE TABLE user_roles (
    user_id BINARY(16) NOT NULL,
    role_id BINARY(16) NOT NULL,
    PRIMARY KEY (user_id, role_id),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE
);

CREATE TABLE file_metadata (
    id            BINARY(16) PRIMARY KEY,
    original_name VARCHAR(255) NOT NULL,
    stored_name   VARCHAR(255) NOT NULL UNIQUE,
    content_type  VARCHAR(100) NOT NULL,
    size          BIGINT       NOT NULL,
    storage_path  VARCHAR(500) NOT NULL,
    public_url    VARCHAR(500),
    uploaded_by   BINARY(16)   NOT NULL,
    uploaded_at   DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    FOREIGN KEY (uploaded_by) REFERENCES users(id)
);

-- Seed default roles (UUIDs generated as BINARY(16))
INSERT INTO roles (id, name) VALUES (UUID_TO_BIN(UUID()), 'ROLE_USER');
INSERT INTO roles (id, name) VALUES (UUID_TO_BIN(UUID()), 'ROLE_MODERATOR');
INSERT INTO roles (id, name) VALUES (UUID_TO_BIN(UUID()), 'ROLE_ADMIN');

-- Indexes
CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_email    ON users(email);
CREATE INDEX idx_file_uploader  ON file_metadata(uploaded_by);
