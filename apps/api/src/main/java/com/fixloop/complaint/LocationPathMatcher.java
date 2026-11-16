package com.fixloop.complaint;

/** Prefix matching on materialised location paths with or without trailing slashes. */
public final class LocationPathMatcher {
    private LocationPathMatcher() {
    }

    public static String normalize(String path) {
        if (path == null || path.isBlank()) {
            return "";
        }
        String trimmed = path.trim();
        while (trimmed.length() > 1 && trimmed.endsWith("/")) {
            trimmed = trimmed.substring(0, trimmed.length() - 1);
        }
        return trimmed;
    }

    public static boolean matchesScope(String locationPath, String scopePath) {
        String loc = normalize(locationPath);
        String scope = normalize(scopePath);
        if (loc.isEmpty() || scope.isEmpty()) {
            return false;
        }
        if ("/".equals(scope)) {
            return loc.startsWith("/");
        }
        return loc.equals(scope) || loc.startsWith(scope + "/");
    }
}
