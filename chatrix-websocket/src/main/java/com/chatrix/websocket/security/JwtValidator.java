package com.chatrix.websocket.security;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.JwtException;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;

/**
 * Validates JWT tokens produced by the chatrix-api module.
 * The secret key must match the one configured in chatrix-api.
 * Set via environment variable JWT_SECRET.
 */
public class JwtValidator {

    private static final Logger log = LoggerFactory.getLogger(JwtValidator.class);
    private static final String USER_ID_CLAIM = "userId";
    private static final String DEFAULT_SECRET =
            "chatrix-default-secret-change-in-production-min32chars";

    private static final JwtValidator INSTANCE = new JwtValidator();

    private final SecretKey secretKey;

    private JwtValidator() {
        String secret = System.getenv("JWT_SECRET");
        if (secret == null || secret.isBlank()) {
            log.warn("JWT_SECRET env var not set — using default (insecure for production)");
            secret = DEFAULT_SECRET;
        }
        this.secretKey = Keys.hmacShaKeyFor(secret.getBytes(StandardCharsets.UTF_8));
    }

    public static JwtValidator getInstance() {
        return INSTANCE;
    }

    public boolean isValid(String token) {
        try {
            Jwts.parser().verifyWith(secretKey).build().parseSignedClaims(token);
            return true;
        } catch (JwtException | IllegalArgumentException e) {
            log.debug("Invalid JWT token: {}", e.getMessage());
            return false;
        }
    }

    public String extractUserId(String token) {
        Claims claims = Jwts.parser()
                .verifyWith(secretKey)
                .build()
                .parseSignedClaims(token)
                .getPayload();
        // Support both "userId" claim and standard "sub"
        String userId = claims.get(USER_ID_CLAIM, String.class);
        return userId != null ? userId : claims.getSubject();
    }
}
