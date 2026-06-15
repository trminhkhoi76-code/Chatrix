package com.chatrix.websocket.server;

import com.chatrix.websocket.handler.WebSocketFrameHandler;
import com.chatrix.websocket.handler.JwtAuthHandshakeHandler;
import io.netty.channel.ChannelInitializer;
import io.netty.channel.ChannelPipeline;
import io.netty.channel.socket.SocketChannel;
import io.netty.handler.codec.http.HttpObjectAggregator;
import io.netty.handler.codec.http.HttpServerCodec;
import io.netty.handler.codec.http.websocketx.WebSocketServerProtocolHandler;
import io.netty.handler.codec.http.websocketx.extensions.compression.WebSocketServerCompressionHandler;
import io.netty.handler.stream.ChunkedWriteHandler;
import io.netty.handler.timeout.IdleStateHandler;

import java.util.concurrent.TimeUnit;

public class WebSocketServerInitializer extends ChannelInitializer<SocketChannel> {

    private static final String WS_PATH = "/ws/chat";
    private static final int MAX_FRAME_SIZE = 65536;
    private static final int MAX_CONTENT_LENGTH = 65536;

    @Override
    protected void initChannel(SocketChannel ch) {
        ChannelPipeline pipeline = ch.pipeline();

        // Idle connection detection: 60s read timeout
        pipeline.addLast("idleStateHandler", new IdleStateHandler(60, 0, 0, TimeUnit.SECONDS));

        // HTTP codec
        pipeline.addLast("httpServerCodec", new HttpServerCodec());
        pipeline.addLast("chunkedWriter", new ChunkedWriteHandler());
        pipeline.addLast("httpAggregator", new HttpObjectAggregator(MAX_CONTENT_LENGTH));

        // WebSocket compression
        pipeline.addLast("wsCompression", new WebSocketServerCompressionHandler());

        // JWT authentication during handshake (validates token from query param or header)
        pipeline.addLast("jwtAuth", new JwtAuthHandshakeHandler());

        // WebSocket protocol handler
        pipeline.addLast("wsProtocol", new WebSocketServerProtocolHandler(WS_PATH, null, true, MAX_FRAME_SIZE));

        // Business logic handler
        pipeline.addLast("wsFrameHandler", new WebSocketFrameHandler());
    }
}
