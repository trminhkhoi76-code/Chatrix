package com.chatrix.websocket.handler;

import com.chatrix.websocket.session.ChatSessionRegistry;
import com.chatrix.websocket.model.ChatMessage;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import io.netty.channel.Channel;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.SimpleChannelInboundHandler;
import io.netty.handler.codec.http.websocketx.TextWebSocketFrame;
import io.netty.handler.codec.http.websocketx.WebSocketFrame;
import io.netty.handler.timeout.IdleStateEvent;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class WebSocketFrameHandler extends SimpleChannelInboundHandler<WebSocketFrame> {

    private static final Logger log = LoggerFactory.getLogger(WebSocketFrameHandler.class);

    private static final ObjectMapper MAPPER = new ObjectMapper()
            .registerModule(new JavaTimeModule());

    private final ChatSessionRegistry sessionRegistry = ChatSessionRegistry.getInstance();

    @Override
    public void channelActive(ChannelHandlerContext ctx) {
        log.debug("Channel active: {}", ctx.channel().id());
        sessionRegistry.register(ctx.channel());
    }

    @Override
    public void channelInactive(ChannelHandlerContext ctx) {
        log.debug("Channel inactive: {}", ctx.channel().id());
        sessionRegistry.unregister(ctx.channel());
    }

    @Override
    protected void channelRead0(ChannelHandlerContext ctx, WebSocketFrame frame) throws Exception {
        if (frame instanceof TextWebSocketFrame textFrame) {
            handleTextFrame(ctx.channel(), textFrame.text());
        } else {
            log.warn("Unsupported frame type: {}", frame.getClass().getSimpleName());
        }
    }

    private void handleTextFrame(Channel channel, String payload) throws Exception {
        ChatMessage message = MAPPER.readValue(payload, ChatMessage.class);
        log.debug("Received message type={} from channel={}", message.getType(), channel.id());

        switch (message.getType()) {
            case PING -> sendPong(channel);
            case JOIN_ROOM -> sessionRegistry.joinRoom(channel, message.getRoomId());
            case LEAVE_ROOM -> sessionRegistry.leaveRoom(channel, message.getRoomId());
            case CHAT -> broadcastToRoom(channel, message);
            case DIRECT -> sendDirect(channel, message);
            default -> log.warn("Unknown message type: {}", message.getType());
        }
    }

    private void broadcastToRoom(Channel sender, ChatMessage message) throws Exception {
        String json = MAPPER.writeValueAsString(message);
        sessionRegistry.broadcastToRoom(message.getRoomId(), sender, new TextWebSocketFrame(json));
    }

    private void sendDirect(Channel sender, ChatMessage message) throws Exception {
        String json = MAPPER.writeValueAsString(message);
        sessionRegistry.sendToUser(message.getRecipientId(), new TextWebSocketFrame(json));
    }

    private void sendPong(Channel channel) throws Exception {
        ChatMessage pong = new ChatMessage();
        pong.setType(ChatMessage.MessageType.PONG);
        channel.writeAndFlush(new TextWebSocketFrame(MAPPER.writeValueAsString(pong)));
    }

    @Override
    public void userEventTriggered(ChannelHandlerContext ctx, Object evt) {
        if (evt instanceof IdleStateEvent) {
            log.info("Channel idle, closing: {}", ctx.channel().id());
            ctx.close();
        }
    }

    @Override
    public void exceptionCaught(ChannelHandlerContext ctx, Throwable cause) {
        log.error("WebSocket error on channel {}: {}", ctx.channel().id(), cause.getMessage(), cause);
        ctx.close();
    }
}
