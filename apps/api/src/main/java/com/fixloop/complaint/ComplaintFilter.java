package com.fixloop.complaint;

import java.util.List;
import java.util.UUID;

public record ComplaintFilter(
        List<ComplaintStatus> statuses,
        UUID departmentId,
        Boolean mine,
        Boolean assignedToMe,
        Boolean unclaimed,
        Boolean overdue,
        String q,
        String sort) {
}
