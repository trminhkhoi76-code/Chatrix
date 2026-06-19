# Chatrix WebSocket — Technical Reference

This document covers the internal mechanics of `chatrix-websocket`: Netty server bootstrap, channel pipeline, JWT handshake, session lifecycle, message routing, and known limitations.

---

## Table of Contents

- [Architecture](#architecture)
- [Server Bootstrap](#server-bootstrap)
- [Channel Pipeline](#channel-pipeline)
- [JWT Authentication on Handshake](#jwt-authentication-on-handshake)
- [Session Registry Internals](#session-registry-internals)
- [Message Protocol](#message-protocol)
- [Message Routing & Broadcast](#message-routing--broadcast)
- [Session Lifecycle](#session-lifecycle)
- [Keepalive & Idle Timeout](#keepalive--idle-timeout)
- [Error Handling](#error-handling)
- [Known Limitations](#known-limitations)

---

## Architecture

```
chatrix-websocket (Netty 4.1.109 — pure Java, no framework)

┌──────────────────────────────────────────────────────────────────┐
│  WebSocketServerApplication.main()                               │
│    └─► WebSocketServer.start()                                   │
│          ├─ bossGroup   (NioEventLoopGroup, 1 thread)            │
│          ├─ workerGroup (NioEventLoopGroup, CPU*2 threads)        │
│          └─ ServerBootstrap → bind(:8081)                        │
│                                                                  │
│  Per-connection channel pipeline (WebSocketServerInitializer):   │
│                                                                  │
│   [1] IdleStateHandler          60s read timeout                 │
│   [2] HttpServerCodec           HTTP ↔ bytes                     │
│   [3] ChunkedWriteHandler       large write support              │
│   [4] HttpObjectAggregator      max 65 536 bytes                 │
│   [5] WsServerCompressionHandler permessage-deflate              │
│   [6] JwtAuthHandshakeHandler   custom — auth gate               │
│   [7] WsServerProtocolHandler   upgrade + frame codec            │
│   [8] WebSocketFrameHandler     business logic                   │
└──────────────────────────────────────────────────────────────────┘
```

The server is entirely asynchronous and non-blocking. All I/O runs on Netty's event loop threads; no blocking code exists in the handlers.

---

## Server Bootstrap

**Entry point**: `WebSocketServerApplication.main()`

```
Port resolution order:
  1. CLI argument: java -jar ... 8082
  2. Environment variable: WS_PORT
  3. Hard-coded default: 8081
```

**`WebSocketServer.start()`**:

1. Creates two `NioEventLoopGroup`s — `bossGroup` (1 thread, accepts connections) and `workerGroup` (default: `2 × availableProcessors`, processes I/O).
2. Configures `ServerBootstrap` with `NioServerSocketChannel` and `WebSocketServerInitializer` as the child handler.
3. Binds to the resolved port with `serverBootstrap.bind(port).sync()`.
4. Registers a JVM shutdown hook that calls `bossGroup.shutdownGracefully()` and `workerGroup.shutdownGracefully()`.

---

## Channel Pipeline

`WebSocketServerInitializer.initChannel(SocketChannel ch)` inserts the following handlers **in order** into each new connection's pipeline:

```
Inbound direction  (client → server)  ──► reads top-to-bottom
Outbound direction (server → client)  ──► writes bottom-to-top

 Handler                          Class                              Role
─────────────────────────────────────────────────────────────────────────────
 idleStateHandler          IdleStateHandler(60, 0, 0)    Fires IdleStateEvent
                                                          after 60s of no read

 httpServerCodec           HttpServerCodec                Decodes HTTP request
                                                          bytes into objects

 chunkedWriter             ChunkedWriteHandler            Supports chunked
                                                          write streams

 httpAggregator            HttpObjectAggregator(65536)    Assembles HTTP parts
                                                          into FullHttpRequest

 wsCompression             WsServerCompressionHandler     Negotiates and
                                                          applies per-message
                                                          deflate compression

 jwtAuth  ◄── REMOVED      JwtAuthHandshakeHandler        Validates JWT before
              after auth                                   upgrade; removes
                                                          itself on success

 wsProtocol                WsServerProtocolHandler        Performs HTTP→WS
                           ("/ws/chat")                   upgrade (101),
                                                          encodes/decodes frames

 wsFrameHandler            WebSocketFrameHandler          Application logic:
                                                          routing, broadcast,
                                                          session management
─────────────────────────────────────────────────────────────────────────────
```

### Handler interaction during upgrade

```
client                   pipeline
  │                         │
  │── GET /ws/chat?token ──► idleStateHandler (pass-through)
  │                         httpServerCodec   (decode HTTP)
  │                         httpAggregator    (assemble FullHttpRequest)
  │                         jwtAuth ◄─────── inspects FullHttpRequest
  │                           │  invalid JWT → write 401, close
  │                           │  valid JWT   → set channel attr USER_ID,
  │                           │               strip ?token from URI,
  │                           │               ctx.fireChannelRead(request),
  │                           │               remove self from pipeline
  │                         wsProtocol ◄──── sees clean /ws/chat URI,
  │                                          performs RFC 6455 handshake
  │◄── HTTP 101 ─────────────┘
  │                         wsFrameHandler.channelActive() ← now active
```

---

## JWT Authentication on Handshake

**Class**: `JwtAuthHandshakeHandler extends ChannelInboundHandlerAdapter`

This handler intercepts the raw `FullHttpRequest` that arrives before the WebSocket upgrade.

### Token extraction

```
1. Authorization header:  "Authorization: Bearer <token>"
2. Query parameter:       /ws/chat?token=<token>
```

If neither is present → HTTP 401 + close.

### Validation

`JwtValidator` (singleton) wraps JJWT 0.12.5:

```java
Jwts.parser()
    .verifyWith(secretKey)      // HMAC-SHA, key = JWT_SECRET env var
    .build()
    .parseSignedClaims(token)   // throws JwtException if invalid/expired
```

`JWT_SECRET` fallback value: `"chatrix-default-secret-change-in-production-min32chars"` (≥ 32 bytes satisfies HMAC-SHA minimum).

### userId extraction

```java
Claims claims = parser.parseSignedClaims(token).getPayload();
String userId = claims.get("userId", String.class);   // primary
if (userId == null) userId = claims.getSubject();      // fallback: "sub"
```

The `userId` claim is a `UUID.toString()` set by `chatrix-api`'s `JwtTokenProvider.buildToken()`.

### Post-validation steps

```
1. channel.attr(ChannelAttributes.USER_ID).set(userId)
   → Stored as channel attribute, available to all downstream handlers.

2. URI rewrite:
   "/ws/chat?token=eyJ..." → "/ws/chat"
   Required because WebSocketServerProtocolHandler matches exact path.
   Without this step the upgrade would fail with 404.

3. ctx.pipeline().remove(this)
   → Handler removes itself; not needed after auth is done.

4. ctx.fireChannelRead(request)
   → Passes the (rewritten) FullHttpRequest to the next handler.
```

### 401 response format

```
HTTP/1.1 401 Unauthorized
Content-Length: 0
Connection: close
```

---

## Session Registry Internals

**Class**: `ChatSessionRegistry` — lazy-initialized singleton (`INSTANCE` is a `static final` field).

### Data structures

```java
ChannelGroup                allChannels     // DefaultChannelGroup(executor)
Map<String, Channel>        userChannelMap  // ConcurrentHashMap: userId → Channel
Map<String, ChannelGroup>   roomGroups      // ConcurrentHashMap: roomId → ChannelGroup
```

`DefaultChannelGroup` automatically removes closed channels from its set, making stale-channel cleanup free.

### Thread safety

All three collections are either `DefaultChannelGroup` (internally synchronized) or `ConcurrentHashMap`. Handler methods run on Netty's I/O threads; no additional locking is needed.

### Method contracts

| Method | Complexity | Notes |
|--------|-----------|-------|
| `register(channel)` | O(1) | Adds to `allChannels` |
| `unregister(channel)` | O(R) where R = room count | Removes from all room groups, scans `userChannelMap` values |
| `associateUser(userId, channel)` | O(1) | Updates `userChannelMap` |
| `joinRoom(channel, roomId)` | O(1) amortized | Creates `DefaultChannelGroup` lazily |
| `leaveRoom(channel, roomId)` | O(1) | Removes group entry if empty |
| `broadcastToRoom(roomId, sender, frame)` | O(N) where N = room size | Skips sender and closed channels |
| `sendToUser(userId, frame)` | O(1) | Lookup by userId |

### Known gap: `associateUser` is never called

`WebSocketFrameHandler.channelActive()` calls `register(channel)` but not `associateUser(userId, channel)`, so `userChannelMap` stays empty and `sendToUser()` always misses. See [Known Limitations](#known-limitations).

---

## Message Protocol

All WebSocket frames are **UTF-8 text frames** containing a JSON object.

### ChatMessage schema

```java
public class ChatMessage {
    public enum MessageType {
        PING, PONG,
        JOIN_ROOM, LEAVE_ROOM,
        CHAT, DIRECT,
        SYSTEM, ERROR
    }

    MessageType type;
    String      roomId;         // room identifier (CHAT, JOIN_ROOM, LEAVE_ROOM)
    String      senderId;       // server-populated from JWT
    String      senderName;     // server-populated from JWT
    String      recipientId;    // target userId (DIRECT only)
    String      content;        // message text
    String      attachmentUrl;  // optional file URL
    Instant     timestamp;      // server-populated via Instant.now()
}
```

`ObjectMapper` is configured with `JavaTimeModule`, so `Instant` serializes as ISO-8601 string.

### Field ownership

| Field | Set by | How |
|-------|--------|-----|
| `type` | Client | Required in every message |
| `roomId` | Client | For CHAT / JOIN_ROOM / LEAVE_ROOM |
| `recipientId` | Client | For DIRECT |
| `content` | Client | Message text |
| `attachmentUrl` | Client | Optional |
| `senderId` | Server | From `ChannelAttributes.USER_ID` |
| `senderName` | Server | Copied from `senderName` field in the incoming message (client-provided; not yet validated against DB) |
| `timestamp` | Server | `Instant.now()` at processing time |

### Message type reference

| Type | Direction | Required client fields | Server action |
|------|-----------|----------------------|---------------|
| `PING` | C→S | `type` | Reply with `PONG` |
| `PONG` | S→C | — | Server only |
| `JOIN_ROOM` | C→S | `type`, `roomId` | `sessionRegistry.joinRoom(channel, roomId)` |
| `LEAVE_ROOM` | C→S | `type`, `roomId` | `sessionRegistry.leaveRoom(channel, roomId)` |
| `CHAT` | C→S | `type`, `roomId`, `content` | Broadcast to room (excluding sender) |
| `DIRECT` | C→S | `type`, `recipientId`, `content` | Unicast to recipient |
| `SYSTEM` | S→C | — | Server-generated notifications |
| `ERROR` | S→C | — | Server-generated error reports |

---

## Message Routing & Broadcast

### CHAT — room broadcast

```
WebSocketFrameHandler.channelRead0()
  │
  ├─ parse JSON → ChatMessage
  ├─ message.setSenderId(channel.attr(USER_ID).get())
  ├─ message.setTimestamp(Instant.now())
  └─ broadcastToRoom(channel, message)
       │
       └─ sessionRegistry.broadcastToRoom(roomId, sender, frame)
            │
            ├─ ChannelGroup group = roomGroups.get(roomId)
            │  if null → log warn "unknown room", return
            │
            ├─ for each ch in group:
            │    if ch != sender && ch.isActive():
            │      ch.writeAndFlush(frame.retainedDuplicate())
            │
            └─ frame.release()   ← original frame released once
```

`retainedDuplicate()` increments the reference count so each recipient gets its own logically independent buffer without copying bytes. The original is released after the loop, maintaining the Netty reference-counted buffer invariant.

### DIRECT — unicast

```
WebSocketFrameHandler.channelRead0()
  │
  └─ sendDirect(channel, message)
       │
       ├─ message.setSenderId(...)
       ├─ message.setTimestamp(...)
       └─ sessionRegistry.sendToUser(recipientId, frame)
            │
            ├─ Channel target = userChannelMap.get(userId)
            │
            ├─ if target == null || !target.isActive():
            │    log warn "user not connected"
            │    frame.release()
            │    return
            │
            └─ target.writeAndFlush(frame.retainedDuplicate())
               frame.release()
```

### PING → PONG

```java
private void sendPong(Channel channel) {
    ChatMessage pong = new ChatMessage();
    pong.setType(MessageType.PONG);
    pong.setTimestamp(Instant.now());
    channel.writeAndFlush(new TextWebSocketFrame(objectMapper.writeValueAsString(pong)));
}
```

### JOIN_ROOM / LEAVE_ROOM

```
JOIN_ROOM:
  sessionRegistry.joinRoom(channel, roomId)
    roomGroups.computeIfAbsent(roomId,
        id -> new DefaultChannelGroup(GlobalEventExecutor.INSTANCE))
    .add(channel)

LEAVE_ROOM:
  sessionRegistry.leaveRoom(channel, roomId)
    ChannelGroup group = roomGroups.get(roomId)
    if group != null:
      group.remove(channel)
      if group.isEmpty(): roomGroups.remove(roomId)
```

A channel can be a member of multiple rooms simultaneously (no single-room constraint in the current data model).

---

## Session Lifecycle

```
                    CLIENT                      chatrix-websocket
                      │                               │
  ── connect ─────────┤                               │
                      │── TCP SYN ───────────────────►│ bossGroup accepts
                      │                               │ workerGroup handles I/O
                      │── HTTP GET /ws/chat?token ───►│ httpServerCodec decodes
                      │                               │ httpAggregator assembles
                      │                               │ JwtAuthHandshakeHandler:
                      │                               │   extract token
                      │                               │   JwtValidator.isValid()
                      │                               │
                      │           [invalid token]     │
                      │◄── HTTP 401 ──────────────────│ close channel
                      │                               │
                      │           [valid token]       │
                      │                               │   set USER_ID attr
                      │                               │   rewrite URI
                      │                               │   remove self from pipeline
                      │                               │ WsServerProtocolHandler:
                      │◄── HTTP 101 Switching ────────│   upgrade complete
                      │                               │
  ── active ──────────┤                               │ channelActive()
                      │                               │   sessionRegistry.register()
                      │                               │   allChannels.add(channel)
                      │                               │   [BUG: associateUser not called]
                      │                               │
                      │── JOIN_ROOM ─────────────────►│ roomGroups[roomId].add(channel)
                      │                               │
                      │── CHAT ──────────────────────►│ broadcastToRoom()
                      │◄── CHAT (from others) ─────── │
                      │                               │
                      │── PING ──────────────────────►│
                      │◄── PONG ──────────────────────│
                      │                               │
  ── idle 60s ─────── │                               │ IdleStateHandler fires
                      │                               │ userEventTriggered(IdleStateEvent)
                      │                               │   channel.close()
                      │                               │
  ── disconnect ───────┤                               │ channelInactive()
                      │                               │   sessionRegistry.unregister()
                      │                               │     allChannels.remove(channel)
                      │                               │     userChannelMap: scan & remove
                      │                               │     roomGroups: remove from all
```

### Channel attribute availability

```
After JwtAuthHandshakeHandler runs:
  channel.attr(ChannelAttributes.USER_ID) → String UUID of authenticated user

After JOIN_ROOM is processed:
  channel.attr(ChannelAttributes.ROOM_ID) → defined in ChannelAttributes
                                             but currently never written
```

---

## Keepalive & Idle Timeout

`IdleStateHandler(60, 0, 0)` is configured for **reader idle** only:

```
readerIdleTime  = 60s  → fires IdleStateEvent(READER_IDLE) if no read in 60s
writerIdleTime  = 0    → disabled
allIdleTime     = 0    → disabled
```

Handler response in `WebSocketFrameHandler.userEventTriggered()`:

```java
if (evt instanceof IdleStateEvent e && e.state() == IdleState.READER_IDLE) {
    log.warn("Channel idle, closing: {}", ctx.channel().remoteAddress());
    ctx.close();
}
```

**Client responsibility**: Send a `PING` frame at least once every 60 seconds to keep the connection alive. The server replies with `PONG`. No WebSocket-level ping frames (`PingWebSocketFrame`) are used — keepalive is handled at the application protocol level.

---

## Error Handling

### Handshake failure

| Cause | Response |
|-------|---------|
| Missing token | HTTP 401, `Content-Length: 0`, connection closed |
| Invalid signature | HTTP 401, connection closed |
| Expired token | HTTP 401, connection closed |

### Frame processing errors

| Situation | Handler action |
|-----------|---------------|
| Non-text frame (binary, ping, etc.) | Silently ignored (handler only processes `TextWebSocketFrame`) |
| Malformed JSON | `log.warn`, frame dropped, channel stays open |
| Unknown `type` field | `log.warn`, frame dropped |
| CHAT to non-existent room | `log.warn`, no-op |
| DIRECT to offline user | `log.warn`, frame released |
| Exception in handler | `exceptionCaught()` logs, closes channel |

### `exceptionCaught()` behavior

```java
@Override
public void exceptionCaught(ChannelHandlerContext ctx, Throwable cause) {
    log.error("WebSocket error on {}: {}", ctx.channel().remoteAddress(), cause.getMessage());
    ctx.close();
}
```

Any unhandled exception terminates the connection. The client must reconnect and re-authenticate.

---

## Known Limitations

### 1. DIRECT messages always fail (critical bug)

`channelActive()` never calls `sessionRegistry.associateUser(userId, channel)`, so `userChannelMap` is always empty. Every DIRECT message is silently dropped with a warning log.

**Fix**:
```java
// WebSocketFrameHandler.channelActive()
@Override
public void channelActive(ChannelHandlerContext ctx) {
    Channel ch = ctx.channel();
    sessionRegistry.register(ch);
    String userId = ch.attr(ChannelAttributes.USER_ID).get();
    if (userId != null) {
        sessionRegistry.associateUser(userId, ch);   // ← missing line
    }
}
```

### 2. `senderName` is client-supplied and unverified

`ChatMessage.senderName` comes from the incoming JSON, not from a database lookup or JWT claim. Any connected user can impersonate any display name.

### 3. Single-server only — no horizontal scalability

`ChatSessionRegistry` is in-memory. Multiple WebSocket server instances cannot share room or user state. To scale out, room broadcasts must go through a shared pub/sub layer (e.g., Redis Streams or Redis pub/sub) so that a message sent to node A is relayed to users connected to node B.

Redis is already configured in `chatrix-api` but is not wired into the WebSocket server.

### 4. No message persistence

Messages are broadcast and forgotten. There is no history, no replay on reconnect, and no guaranteed delivery. If a recipient is temporarily disconnected, the message is lost.

### 5. ROOM_ID channel attribute is defined but never written

`ChannelAttributes.ROOM_ID` exists but nothing sets it. A channel can be in multiple rooms simultaneously, so a single attribute is insufficient for multi-room membership tracking — the `roomGroups` map in `ChatSessionRegistry` is the correct mechanism.

### 6. No rate limiting or backpressure

A single client can flood the server with messages. Netty's channel pipeline has no throttle, and there is no per-user message rate limit.

### 7. Token expiry is not checked after handshake

The JWT is validated once at upgrade time. If the token expires during an active session, the connection remains open. The server has no mechanism to force-close sessions with expired tokens.

### 8. `unregister()` scans `userChannelMap` values linearly

```java
userChannelMap.entrySet().removeIf(e -> e.getValue() == channel);
```

This is O(U) where U is the total number of connected users. At large scale, a reverse lookup map (`channelUserMap`) would make this O(1).

---

## Sequence Diagrams

### Full connection + room chat

```
 Alice                  chatrix-api            chatrix-websocket
   │                        │                         │
   │── POST /auth/login ───►│                         │
   │◄── { accessToken } ────│                         │
   │                        │                         │
   │── WS upgrade ?token ───────────────────────────► │
   │                        │             validate JWT │
   │◄── 101 Switching ─────────────────────────────── │
   │                        │     channelActive()      │
   │                        │     register(channel)    │
   │                        │     [missing: assocUser] │
   │                        │                         │
   │── JOIN_ROOM "general" ─────────────────────────► │
   │                        │     joinRoom(ch,"gen")   │
   │                        │                         │
   │── CHAT "Hello" ────────────────────────────────► │
   │                        │     broadcastToRoom()    │
   │                        │          │              │
   │◄── CHAT (Alice msg) ─────────────────────────── Bob (other member)
   │                        │                         │
   │── PING ────────────────────────────────────────► │
   │◄── PONG ─────────────────────────────────────── │
   │                        │                         │
   │── LEAVE_ROOM "general" ───────────────────────► │
   │                        │     leaveRoom(ch,"gen")  │
   │                        │                         │
   │── close ───────────────────────────────────────► │
   │                        │     channelInactive()    │
   │                        │     unregister(channel)  │
```

### Failed authentication

```
 Client                      chatrix-websocket
   │                               │
   │── WS upgrade (no token) ────► │
   │                               │ JwtAuthHandshakeHandler:
   │                               │   no token found
   │◄── HTTP 401 ─────────────────  │   write 401, close
   │                               │
   │── WS upgrade (bad token) ───► │
   │                               │ JwtValidator.isValid() → false
   │◄── HTTP 401 ─────────────────  │   write 401, close
```