package com.chatrix.websocket.session;

import io.netty.channel.Channel;
import io.netty.channel.group.ChannelGroup;
import io.netty.channel.group.DefaultChannelGroup;
import io.netty.handler.codec.http.websocketx.WebSocketFrame;
import io.netty.util.concurrent.GlobalEventExecutor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Thread-safe registry tracking active WebSocket channels.
 * Maps userId -> Channel and roomId -> ChannelGroup.
 */
public class ChatSessionRegistry {

    private static final Logger log = LoggerFactory.getLogger(ChatSessionRegistry.class);

    private static final ChatSessionRegistry INSTANCE = new ChatSessionRegistry();

    /** All active connected channels */
    private final ChannelGroup allChannels = new DefaultChannelGroup(GlobalEventExecutor.INSTANCE);

    /** userId -> Channel (for direct messages) */
    private final Map<String, Channel> userChannelMap = new ConcurrentHashMap<>();

    /** roomId -> ChannelGroup */
    private final Map<String, ChannelGroup> roomGroups = new ConcurrentHashMap<>();

    private ChatSessionRegistry() {}

    public static ChatSessionRegistry getInstance() {
        return INSTANCE;
    }

    public void register(Channel channel) {
        allChannels.add(channel);
        log.debug("Channel registered: {} | total={}", channel.id(), allChannels.size());
    }

    public void unregister(Channel channel) {
        allChannels.remove(channel);
        userChannelMap.values().remove(channel);
        roomGroups.values().forEach(group -> group.remove(channel));
        log.debug("Channel unregistered: {} | total={}", channel.id(), allChannels.size());
    }

    public void associateUser(String userId, Channel channel) {
        userChannelMap.put(userId, channel);
    }

    public void joinRoom(Channel channel, String roomId) {
        roomGroups.computeIfAbsent(roomId,
                id -> new DefaultChannelGroup(GlobalEventExecutor.INSTANCE)).add(channel);
        log.debug("Channel {} joined room {}", channel.id(), roomId);
    }

    public void leaveRoom(Channel channel, String roomId) {
        ChannelGroup group = roomGroups.get(roomId);
        if (group != null) {
            group.remove(channel);
            if (group.isEmpty()) {
                roomGroups.remove(roomId);
            }
        }
    }

    public void broadcastToRoom(String roomId, Channel sender, WebSocketFrame frame) {
        ChannelGroup group = roomGroups.get(roomId);
        if (group == null) {
            log.warn("broadcastToRoom: room {} not found", roomId);
            return;
        }
        group.stream()
                .filter(ch -> ch != sender && ch.isActive())
                .forEach(ch -> ch.writeAndFlush(frame.retainedDuplicate()));
        frame.release();
    }

    public void sendToUser(String userId, WebSocketFrame frame) {
        Channel ch = userChannelMap.get(userId);
        if (ch != null && ch.isActive()) {
            ch.writeAndFlush(frame);
        } else {
            log.warn("sendToUser: user {} is not online", userId);
            frame.release();
        }
    }

    public int getOnlineCount() {
        return allChannels.size();
    }
}
