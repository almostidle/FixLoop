package com.fixloop.notification;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import com.fixloop.auth.AuthService;
import com.fixloop.common.ApiException;
import com.fixloop.notification.dto.NotificationListResponse;
import com.fixloop.notification.dto.NotificationResponse;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Manages in-app notifications backed by {@code notifications_outbox}. */
@Service
public class NotificationService {
    private static final int DEFAULT_LIMIT = 50;

    private final NotificationRepository repository;
    private final AuthService authService;

    public NotificationService(NotificationRepository repository, AuthService authService) {
        this.repository = repository;
        this.authService = authService;
    }

    @Transactional(readOnly = true)
    public NotificationListResponse listForUser(UUID userId) {
        authService.requireActiveUser(userId);
        List<NotificationResponse> items = repository.findInAppForUser(userId, DEFAULT_LIMIT);
        long unreadCount = repository.countUnreadInApp(userId);
        return new NotificationListResponse(unreadCount, items);
    }

    @Transactional
    public NotificationResponse markRead(UUID userId, UUID notificationId) {
        authService.requireActiveUser(userId);
        return repository.markRead(notificationId, userId)
            .orElseThrow(() -> ApiException.notFound("NOTIFICATION_NOT_FOUND",
                "The requested notification does not exist."));
    }

    public void queueInApp(UUID userId, String type, Map<String, Object> payload) {
        if (userId == null) {
            return;
        }
        repository.insertInApp(userId, type, payload);
    }
}
