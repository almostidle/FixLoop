package com.fixloop.complaint.dto;

import java.util.Map;

public record SimilarComplaintsResponse(
        long count,
        String mostCommonStatus,
        Map<String, Long> byStatus) {
}
