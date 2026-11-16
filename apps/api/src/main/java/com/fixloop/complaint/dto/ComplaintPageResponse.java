package com.fixloop.complaint.dto;

import java.util.List;

public record ComplaintPageResponse(
        List<ComplaintSummaryResponse> items,
        int page,
        int size,
        long totalElements,
        int totalPages) {
}
