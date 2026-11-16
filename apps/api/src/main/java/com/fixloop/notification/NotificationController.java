package com.fixloop.notification;

import java.util.UUID;

import com.fixloop.auth.AuthPrincipal;
import com.fixloop.notification.dto.NotificationListResponse;
import com.fixloop.notification.dto.NotificationResponse;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** In-app notifications endpoints backed by {@code notifications_outbox}. */
@RestController
@RequestMapping("/api/v1/notifications")
public class NotificationController {
    private final NotificationService notifications;

    public NotificationController(NotificationService notifications) {
        this.notifications = notifications;
    }

    @GetMapping
    public NotificationListResponse list(@AuthenticationPrincipal Jwt jwt) {
        return notifications.listForUser(AuthPrincipal.userId(jwt));
    }

    @PostMapping("/{id}/read")
    public NotificationResponse markRead(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID id) {
        return notifications.markRead(AuthPrincipal.userId(jwt), id);
    }
}
