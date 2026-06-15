package com.chatrix.websocket.handler;

import io.netty.util.AttributeKey;

public final class ChannelAttributes {

    private ChannelAttributes() {}

    public static final AttributeKey<String> USER_ID = AttributeKey.valueOf("userId");
    public static final AttributeKey<String> ROOM_ID = AttributeKey.valueOf("roomId");
}
