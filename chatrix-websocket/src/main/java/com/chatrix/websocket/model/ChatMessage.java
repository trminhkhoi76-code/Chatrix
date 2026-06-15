package com.chatrix.websocket.model;

import com.fasterxml.jackson.annotation.JsonFormat;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.Instant;

@Data
@NoArgsConstructor
public class ChatMessage {

    public enum MessageType {
        PING, PONG,
        JOIN_ROOM, LEAVE_ROOM,
        CHAT, DIRECT,
        SYSTEM, ERROR
    }

    private MessageType type;

    /** Room identifier for group chat */
    private String roomId;

    /** Sender user ID (populated server-side from JWT) */
    private String senderId;

    /** Sender display name */
    private String senderName;

    /** Recipient user ID for direct messages */
    private String recipientId;

    /** Message text content */
    private String content;

    /** Optional attachment URL */
    private String attachmentUrl;

    @JsonFormat(shape = JsonFormat.Shape.STRING)
    private Instant timestamp = Instant.now();
}
