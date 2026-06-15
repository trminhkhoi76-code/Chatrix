# Chatrix

A real-time chat platform built with Java.

## Architecture

```
chatrix/                        ← Maven parent (multi-module)
├── chatrix-websocket/          ← Netty WebSocket server (real-time chat)
└── chatrix-api/                ← Spring Boot REST API
```

## Modules

### `chatrix-websocket` — Netty WebSocket Server
- Port: `8081` (configurable via `WS_PORT` env var)
- Endpoint: `ws://localhost:8081/ws/chat?token=<jwt>`
- JWT validation on handshake
- Room-based broadcast and direct messages
- Idle connection cleanup (60s timeout)

### `chatrix-api` — Spring Boot REST API
- Port: `8080` (configurable via `API_PORT` env var)
- Swagger UI: `http://localhost:8080/swagger-ui.html`

| Prefix              | Description                              |
|---------------------|------------------------------------------|
| `POST /api/v1/auth/register` | Register a new user              |
| `POST /api/v1/auth/login`    | Login, get JWT tokens            |
| `GET  /api/v1/users/me`      | Get current user profile         |
| `PUT  /api/v1/users/me`      | Update current user profile      |
| `POST /api/v1/files/upload`  | Upload a file                    |
| `GET  /api/v1/files/mine`    | List my uploaded files           |
| `GET  /api/v1/admin/users`   | Admin: list all users            |
| `PATCH /api/v1/admin/users/{id}/enable` | Admin: enable/disable user |

## Running locally

### 1. Start PostgreSQL (or use H2 dev profile)

```bash
docker run -d --name chatrix-db \
  -e POSTGRES_DB=chatrix \
  -e POSTGRES_USER=chatrix \
  -e POSTGRES_PASSWORD=chatrix \
  -p 5432:5432 postgres:16
```

### 2. Build
```bash
mvn clean package -DskipTests
```

### 3. Run the API (dev profile — H2 in-memory)
```bash
cd chatrix-api
mvn spring-boot:run -Dspring-boot.run.profiles=dev
```

### 4. Run the WebSocket server
```bash
cd chatrix-websocket
java -jar target/chatrix-websocket-1.0.0-SNAPSHOT-jar-with-dependencies.jar
```

## Environment Variables

| Variable              | Default                                              | Description                  |
|-----------------------|------------------------------------------------------|------------------------------|
| `JWT_SECRET`          | `chatrix-default-secret-...`                         | **Must be changed in prod**  |
| `DB_URL`              | `jdbc:postgresql://localhost:5432/chatrix`           | Database URL                 |
| `DB_USERNAME`         | `chatrix`                                            | Database user                |
| `DB_PASSWORD`         | `chatrix`                                            | Database password            |
| `API_PORT`            | `8080`                                               | REST API port                |
| `WS_PORT`             | `8081`                                               | WebSocket server port        |
| `UPLOAD_DIR`          | `./uploads`                                          | File upload directory        |
| `BASE_URL`            | `http://localhost:8080`                              | Public base URL for files    |
