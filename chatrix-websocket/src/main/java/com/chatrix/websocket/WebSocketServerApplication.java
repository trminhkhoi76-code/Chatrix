package com.chatrix.websocket;

import com.chatrix.websocket.server.WebSocketServer;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class WebSocketServerApplication {

    private static final Logger log = LoggerFactory.getLogger(WebSocketServerApplication.class);

    public static void main(String[] args) throws InterruptedException {
        int port = parsePort(args);
        log.info("Starting Chatrix WebSocket Server on port {}", port);
        WebSocketServer server = new WebSocketServer(port);
        server.start();
    }

    private static int parsePort(String[] args) {
        if (args.length > 0) {
            try {
                return Integer.parseInt(args[0]);
            } catch (NumberFormatException e) {
                // fall through to default
            }
        }
        String envPort = System.getenv("WS_PORT");
        if (envPort != null && !envPort.isBlank()) {
            try {
                return Integer.parseInt(envPort);
            } catch (NumberFormatException e) {
                // fall through to default
            }
        }
        return 8081;
    }
}
