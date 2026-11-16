package com.fixloop.auth;

import java.util.UUID;

import com.fixloop.common.ApiException;
import org.springframework.security.oauth2.jwt.Jwt;

/** Extracts the authenticated user's UUID from a verified JWT subject. */
public final class AuthPrincipal {
    private AuthPrincipal() {
    }

    public static UUID userId(Jwt jwt) {
        if (jwt == null || jwt.getSubject() == null) {
            throw ApiException.unauthenticated("Your session is no longer valid. Please sign in again.");
        }
        try {
            return UUID.fromString(jwt.getSubject());
        } catch (IllegalArgumentException exception) {
            throw ApiException.unauthenticated("Your session is no longer valid. Please sign in again.");
        }
    }
}
