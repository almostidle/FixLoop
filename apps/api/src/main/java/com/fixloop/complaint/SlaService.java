package com.fixloop.complaint;

import java.time.Duration;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

import org.springframework.stereotype.Service;

/** Computes SLA due timestamps from {@code sla_policies} (category+severity override or default). */
@Service
public class SlaService {
    private final ComplaintRepository repository;

    public SlaService(ComplaintRepository repository) {
        this.repository = repository;
    }

    public Instant computeDueAt(UUID categoryId, ComplaintSeverity severity, Instant referenceTime) {
        Optional<Integer> resolveMinutes = repository.findResolveMinutes(categoryId, severity.name());
        return resolveMinutes
            .map(minutes -> referenceTime.plus(Duration.ofMinutes(minutes)))
            .orElse(null);
    }
}
