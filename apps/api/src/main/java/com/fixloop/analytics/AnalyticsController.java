package com.fixloop.analytics;

import com.fixloop.analytics.dto.AnalyticsSummaryResponse;
import com.fixloop.auth.AuthPrincipal;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** Operational dashboard metrics backed by database views. */
@RestController
@RequestMapping("/api/v1/analytics")
public class AnalyticsController {
    private final AnalyticsService analytics;

    public AnalyticsController(AnalyticsService analytics) {
        this.analytics = analytics;
    }

    @GetMapping("/summary")
    public AnalyticsSummaryResponse summary(@AuthenticationPrincipal Jwt jwt) {
        return analytics.summary(AuthPrincipal.userId(jwt));
    }
}
