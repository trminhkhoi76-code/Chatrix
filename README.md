# Chatrix — Real-Time Chat Platform

A real-time chat platform built with Java, consisting of a Spring Boot REST API and a Netty WebSocket server.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Modules](#modules)
- [Inter-Module Communication](#inter-module-communication)
- [Authentication Flow](#authentication-flow)
- [REST API Reference](#rest-api-reference)
- [WebSocket Protocol](#websocket-protocol)
- [Database Schema](#database-schema)
- [Environment Variables](#environment-variables)
- [Running Locally](#running-locally)
- [Building for Production](#building-for-production)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                           CLIENT (Browser / Mobile)                  │
│                                                                       │
│    HTTP/REST  ───────────────────────────►  chatrix-api :8080        │
│                                                                       │
│    WebSocket  ───────────────────────────►  chatrix-websocket :8081  │
└─────────────────────────────────────────────────────────────────────┘
           │                                        │
           │ JPA / Flyway                           │ Shared JWT Secret
           ▼                                        ▼
     ┌───────────┐                         ┌──────────────────┐
     │   MySQL   │                         │  In-Memory       │
     │ :3306     │                         │  Session Registry│
     └───────────┘                         └──────────────────┘
           │
     ┌───────────┐
     │   Redis   │
     │ :6379     │
     └───────────┘
```

```
chatrix/                        ← Maven parent (multi-module, Java 17)
├── chatrix-api/                ← Spring Boot 3.2.5 REST API
└── chatrix-websocket/          ← Netty 4.1.109 WebSocket server
```

The two modules are **independently deployed** and share **no direct code dependency**. Their only coupling point is the **JWT secret** — the API mints tokens, the WebSocket server validates them.

---

## Modules

### `chatrix-api` — Spring Boot REST API

| Item | Value |
|------|-------|
| Port | `8080` (env: `API_PORT`) |
| Framework | Spring Boot 3.2.5 + Spring Security |
| Database | MySQL (Flyway migrations) |
| Auth | JWT (HMAC-SHA, stateless) |
| Swagger UI | `http://localhost:8080/swagger-ui.html` |
| API Docs | `http://localhost:8080/v3/api-docs` |
| Health | `http://localhost:8080/actuator/health` |

Responsibilities:
- User registration & login
- JWT access + refresh token issuance
- User profile management
- File upload / download
- Admin operations (enable/disable users, role assignment)

### `chatrix-websocket` — Netty WebSocket Server

| Item | Value |
|------|-------|
| Port | `8081` (env: `WS_PORT`) |
| Framework | Netty 4.1.109 |
| Endpoint | `ws://localhost:8081/ws/chat?token=<jwt>` |
| Max frame | 65 536 bytes |
| Idle timeout | 60 seconds (auto-close) |

Responsibilities:
- Real-time bidirectional messaging
- Room-based broadcast (group chat)
- User-to-user direct messages
- JWT validation on handshake (rejects invalid tokens before upgrade)

---

## Inter-Module Communication

### 1. Shared JWT Secret (the only coupling between modules)

```
chatrix-api                         chatrix-websocket
    │                                       │
    │  issues JWT signed with               │  validates JWT signed with
    │  JWT_SECRET                           │  JWT_SECRET (same value)
    ▼                                       ▼
  Access Token ──── sent by client ────► WS Handshake
```

Both modules must be configured with the **same** `JWT_SECRET` environment variable. The API mints the token; the WebSocket server validates the signature independently — no HTTP call between them.

**JWT Payload**

```json
{
  "sub":    "username",
  "userId": "550e8400-e29b-41d4-a716-446655440000",
  "iat":    1718500000,
  "exp":    1718503600
}
```

### 2. REST API → MySQL

Spring Data JPA repositories write/read all persistent state. Flyway applies `V1__init_schema.sql` on first startup.

```
AuthService         ──► UserRepository       ──► MySQL: users
UserService         ──► UserRepository       ──► MySQL: users, user_roles
FileService         ──► FileMetadataRepository ► MySQL: file_metadata
AdminService        ──► UserRepository       ──► MySQL: users, user_roles
                        RoleRepository       ──► MySQL: roles
```

### 3. REST API → Redis

Redis is configured for caching / session support (host/port/password via env vars). Not strictly required for basic auth and messaging.

### 4. REST API → Filesystem

Uploaded files are stored to `UPLOAD_DIR` (default `./uploads`). `FileMetadata` records the `storagePath` (disk) and `publicUrl` (HTTP) for each file.

### 5. WebSocket → In-Memory Session Registry

`ChatSessionRegistry` is a singleton inside the WebSocket server that tracks live connections.

```
ChatSessionRegistry
├── allChannels:    ChannelGroup          ← all connected clients
├── userChannelMap: userId → Channel      ← for direct messages
└── roomGroups:     roomId → ChannelGroup ← for room broadcasts
```

No persistence — session state is lost on server restart.

---

## Authentication Flow

### Step 1: Register

```
POST /api/v1/auth/register
Content-Type: application/json

{
  "username":    "alice",
  "email":       "alice@example.com",
  "password":    "secret123",
  "displayName": "Alice"
}
```

Returns `201 Created` with a `UserResponse`.

### Step 2: Login

```
POST /api/v1/auth/login
Content-Type: application/json

{
  "username": "alice",
  "password": "secret123"
}
```

Returns:

```json
{
  "accessToken":  "<jwt>",
  "refreshToken": "<jwt>",
  "tokenType":    "Bearer",
  "expiresIn":    3600,
  "userId":       "550e8400-...",
  "username":     "alice",
  "roles":        ["ROLE_USER"]
}
```

### Step 3: Call REST API with token

```
GET /api/v1/users/me
Authorization: Bearer <accessToken>
```

### Step 4: Connect to WebSocket

```
ws://localhost:8081/ws/chat?token=<accessToken>
```

The server validates the JWT before the WebSocket upgrade handshake completes. An invalid or missing token results in an HTTP `401` response, and the connection is closed.

### Token Lifetimes

| Token | Default TTL | Env Variable |
|-------|-------------|--------------|
| Access token | 1 hour (3 600 000 ms) | `JWT_ACCESS_EXPIRY_MS` |
| Refresh token | 7 days (604 800 000 ms) | `JWT_REFRESH_EXPIRY_MS` |

---

## REST API Reference

Base URL: `http://localhost:8080`

### Auth (public)

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/v1/auth/register` | Register a new user |
| `POST` | `/api/v1/auth/login` | Login, get JWT tokens |

### Users (requires `Authorization: Bearer <token>`)

| Method | Path | Description | Roles |
|--------|------|-------------|-------|
| `GET` | `/api/v1/users/me` | Get own profile | Any |
| `PUT` | `/api/v1/users/me` | Update own profile | Any |
| `DELETE` | `/api/v1/users/me` | Deactivate own account | Any |
| `GET` | `/api/v1/users/{id}` | Get user by ID | Any |
| `GET` | `/api/v1/users` | List all users (paginated) | ADMIN, MODERATOR |

### Files (requires auth)

| Method | Path | Description | Roles |
|--------|------|-------------|-------|
| `POST` | `/api/v1/files/upload` | Upload file (multipart, max 50 MB) | Any |
| `GET` | `/api/v1/files/{storedName}/download` | Download file | Public |
| `GET` | `/api/v1/files/mine` | List own files (paginated) | Any |
| `DELETE` | `/api/v1/files/{fileId}` | Delete own file | Owner |

### Admin (requires `ROLE_ADMIN`)

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/admin/users` | List all users (paginated) |
| `PATCH` | `/api/v1/admin/users/{userId}/enable` | Enable user |
| `PATCH` | `/api/v1/admin/users/{userId}/disable` | Disable user |
| `POST` | `/api/v1/admin/users/{userId}/roles/{roleName}` | Assign role |
| `DELETE` | `/api/v1/admin/users/{userId}/roles/{roleName}` | Revoke role |
| `DELETE` | `/api/v1/admin/users/{userId}` | Hard-delete user |

### Error Response Format

```json
{
  "status":      400,
  "error":       "Bad Request",
  "message":     "Validation failed",
  "timestamp":   "2026-06-16T10:00:00Z",
  "fieldErrors": {
    "email": "must be a valid email address"
  }
}
```

---

## WebSocket Protocol

### Connection

```
ws://localhost:8081/ws/chat?token=<accessToken>
```

Or with Authorization header:

```
Authorization: Bearer <accessToken>
```

### Message Format

All messages are JSON text frames:

```json
{
  "type":          "CHAT",
  "roomId":        "general",
  "senderId":      "550e8400-...",
  "senderName":    "alice",
  "recipientId":   null,
  "content":       "Hello, world!",
  "attachmentUrl": null,
  "timestamp":     "2026-06-16T10:00:00Z"
}
```

### Message Types

| Type | Direction | Description | Required fields |
|------|-----------|-------------|-----------------|
| `PING` | Client → Server | Keepalive | `type` |
| `PONG` | Server → Client | Keepalive reply | `type` |
| `JOIN_ROOM` | Client → Server | Join a chat room | `type`, `roomId` |
| `LEAVE_ROOM` | Client → Server | Leave a chat room | `type`, `roomId` |
| `CHAT` | Client → Server | Send message to room | `type`, `roomId`, `content` |
| `DIRECT` | Client → Server | Send direct message | `type`, `recipientId`, `content` |
| `SYSTEM` | Server → Client | System notification | `type`, `content` |
| `ERROR` | Server → Client | Error notification | `type`, `content` |

> `senderId` and `senderName` are **populated by the server** from the JWT — the client does not set them.

### Typical Client Session Sequence

```
Client                          chatrix-websocket
  │                                      │
  │── WS upgrade ?token=<jwt> ─────────► │
  │                                      │ validate JWT
  │◄── HTTP 101 Switching Protocols ──── │ store userId in channel attrs
  │                                      │
  │── JOIN_ROOM { roomId: "general" } ─► │ add channel to room group
  │                                      │
  │── CHAT { roomId: "general",          │
  │          content: "hi" } ──────────► │ broadcast to all in "general"
  │                                      │
  │◄── CHAT { senderId, content } ────── │ (from other members)
  │                                      │
  │── DIRECT { recipientId: "...",       │
  │            content: "hey" } ───────► │ unicast to specific user
  │                                      │
  │── PING ───────────────────────────► │
  │◄── PONG ──────────────────────────── │
  │                                      │
  │── LEAVE_ROOM { roomId: "general" } ► │ remove from room group
  │                                      │
  │── close ──────────────────────────► │ unregister from all groups
```

### Idle Timeout

Connections with no activity for **60 seconds** are automatically closed by the server. Clients should send periodic `PING` frames to keep the connection alive.

---

## Database Schema

Managed by **Flyway** (`chatrix-api/src/main/resources/db/migration/V1__init_schema.sql`). Applied automatically on API startup.

### Tables

#### `roles`
| Column | Type | Notes |
|--------|------|-------|
| `id` | `BINARY(16)` | UUID, PK |
| `name` | `ENUM` | `ROLE_USER`, `ROLE_MODERATOR`, `ROLE_ADMIN` |

Seeded with 3 rows on first migration.

#### `users`
| Column | Type | Notes |
|--------|------|-------|
| `id` | `BINARY(16)` | UUID, PK |
| `username` | `VARCHAR(50)` | Unique |
| `email` | `VARCHAR(255)` | Unique |
| `password` | `VARCHAR(255)` | BCrypt hashed |
| `display_name` | `VARCHAR(100)` | |
| `avatar_url` | `VARCHAR(500)` | |
| `enabled` | `BIT(1)` | Default `1` |
| `email_verified` | `BIT(1)` | Default `0` |
| `created_at` | `DATETIME(6)` | |
| `updated_at` | `DATETIME(6)` | |

#### `user_roles`
| Column | Type | Notes |
|--------|------|-------|
| `user_id` | `BINARY(16)` | FK → `users.id` ON DELETE CASCADE |
| `role_id` | `BINARY(16)` | FK → `roles.id` ON DELETE CASCADE |

PK is `(user_id, role_id)`.

#### `file_metadata`
| Column | Type | Notes |
|--------|------|-------|
| `id` | `BINARY(16)` | UUID, PK |
| `original_name` | `VARCHAR(255)` | Original filename |
| `stored_name` | `VARCHAR(255)` | UUID-based, Unique |
| `content_type` | `VARCHAR(100)` | MIME type |
| `size` | `BIGINT` | Bytes |
| `storage_path` | `VARCHAR(500)` | Filesystem path |
| `public_url` | `VARCHAR(500)` | HTTP URL |
| `uploaded_by` | `BINARY(16)` | FK → `users.id` |
| `uploaded_at` | `DATETIME(6)` | |

---

## Environment Variables

### `chatrix-api`

| Variable | Default | Description |
|----------|---------|-------------|
| `API_PORT` | `8080` | Server port |
| `DB_URL` | `jdbc:mysql://localhost:3306/chatrix?...` | MySQL JDBC URL |
| `DB_USERNAME` | `root` | Database user |
| `DB_PASSWORD` | `faber_extract_root_pass` | Database password |
| `JWT_SECRET` | `chatrix-default-secret-change-in-production-min32chars` | **Must be changed in production** |
| `JWT_ACCESS_EXPIRY_MS` | `3600000` | Access token TTL in ms (1 hour) |
| `JWT_REFRESH_EXPIRY_MS` | `604800000` | Refresh token TTL in ms (7 days) |
| `UPLOAD_DIR` | `./uploads` | File storage directory |
| `BASE_URL` | `http://localhost:8080` | Public base URL for file links |
| `REDIS_HOST` | `localhost` | Redis host |
| `REDIS_PORT` | `6379` | Redis port |
| `REDIS_PASSWORD` | `FaberCompany2016` | Redis password |

### `chatrix-websocket`

| Variable | Default | Description |
|----------|---------|-------------|
| `WS_PORT` | `8081` | WebSocket server port |
| `JWT_SECRET` | `chatrix-default-secret-change-in-production-min32chars` | **Must match `chatrix-api`** |

> **Critical**: `JWT_SECRET` must be identical across both modules. If they differ, WebSocket connections will be rejected with `401`.

---

## Running Locally

### Prerequisites

- Java 17+
- Maven 3.8+
- MySQL 8+ running on `localhost:3306` with database `chatrix`
- Redis (optional)

### 1. Create MySQL database

```sql
CREATE DATABASE chatrix CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
```

### 2. Build all modules

```bash
mvn clean package -DskipTests
```

### 3. Start chatrix-api

```bash
# Development profile uses local MySQL
cd chatrix-api
mvn spring-boot:run -Dspring-boot.run.profiles=dev
```

Flyway runs `V1__init_schema.sql` on first startup and seeds the `roles` table.

### 4. Start chatrix-websocket

```bash
# Copy and edit the env file
cp chatrix-websocket/src/main/resources/.env.example chatrix-websocket/.env
# Set WS_PORT and JWT_SECRET to match chatrix-api

java -jar chatrix-websocket/target/chatrix-websocket-1.0.0-SNAPSHOT-jar-with-dependencies.jar
```

### 5. Verify

```bash
# Health check
curl http://localhost:8080/actuator/health

# Register a user
curl -s -X POST http://localhost:8080/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username":"alice","email":"alice@example.com","password":"secret123"}'

# Login and get token
curl -s -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"alice","password":"secret123"}'
```

Then connect to the WebSocket endpoint with the returned `accessToken`.

---

## Building for Production

```bash
mvn clean package -DskipTests

# chatrix-api fat jar
java -jar chatrix-api/target/chatrix-api-*.jar \
  --spring.profiles.active=prod

# chatrix-websocket fat jar (includes all dependencies)
java -jar chatrix-websocket/target/chatrix-websocket-*-jar-with-dependencies.jar
```

Set all environment variables (especially `JWT_SECRET`, `DB_PASSWORD`, `REDIS_PASSWORD`) to secure values before deploying.

**Swagger UI** is available in all profiles at `/swagger-ui.html` and is useful for manual API testing.