package com.chatrix.websocket.handler;

import com.chatrix.websocket.security.JwtValidator;
import io.netty.channel.ChannelFutureListener;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;
import io.netty.handler.codec.http.DefaultFullHttpResponse;
import io.netty.handler.codec.http.FullHttpRequest;
import io.netty.handler.codec.http.HttpResponseStatus;
import io.netty.handler.codec.http.HttpVersion;
import io.netty.handler.codec.http.QueryStringDecoder;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.List;

/**
 * Validates the JWT token before the WebSocket handshake completes.
 * Expects token as query parameter: /ws/chat?token=<jwt>
 * or Authorization header: Bearer <jwt>
 */
public class JwtAuthHandshakeHandler extends ChannelInboundHandlerAdapter {

    private static final Logger log = LoggerFactory.getLogger(JwtAuthHandshakeHandler.class);
    private static final String TOKEN_PARAM = "token";

    private final JwtValidator jwtValidator = JwtValidator.getInstance();

    @Override
    public void channelRead(ChannelHandlerContext ctx, Object msg) throws Exception {
        if (msg instanceof FullHttpRequest request) {
            String token = extractToken(request);

            if (token == null || !jwtValidator.isValid(token)) {
                log.warn("Rejected WebSocket connection - invalid or missing token from {}",
                        ctx.channel().remoteAddress());
                DefaultFullHttpResponse response = new DefaultFullHttpResponse(
                        HttpVersion.HTTP_1_1, HttpResponseStatus.UNAUTHORIZED);
                ctx.writeAndFlush(response).addListener(ChannelFutureListener.CLOSE);
                return;
            }

            String userId = jwtValidator.extractUserId(token);
            ctx.channel().attr(ChannelAttributes.USER_ID).set(userId);
            log.debug("Authenticated WebSocket connection for userId={}", userId);

            // Remove this handler after successful auth — it's only needed for the handshake
            ctx.pipeline().remove(this);
        }
        super.channelRead(ctx, msg);
    }

    private String extractToken(FullHttpRequest request) {
        // 1. Try Authorization header
        String authHeader = request.headers().get("Authorization");
        if (authHeader != null && authHeader.startsWith("Bearer ")) {
            return authHeader.substring(7);
        }
        // 2. Try query param ?token=
        QueryStringDecoder decoder = new QueryStringDecoder(request.uri());
        List<String> tokens = decoder.parameters().get(TOKEN_PARAM);
        if (tokens != null && !tokens.isEmpty()) {
            return tokens.get(0);
        }
        return null;
    }
}
