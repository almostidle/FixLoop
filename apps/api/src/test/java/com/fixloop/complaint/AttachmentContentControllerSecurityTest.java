package com.fixloop.complaint;

import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Instant;
import java.util.UUID;

import com.fixloop.common.ApiException;
import com.fixloop.config.AuthConfiguration;
import com.fixloop.config.SecurityConfiguration;
import com.fixloop.storage.AttachmentLinkService;
import com.fixloop.storage.AttachmentRepository.AttachmentRecord;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(AttachmentContentController.class)
@Import({SecurityConfiguration.class, AuthConfiguration.class})
class AttachmentContentControllerSecurityTest {
    private static final UUID CALLER_ID = UUID.fromString("3f1a6c1e-1111-4a2b-9a10-0c2b7d5e4f60");
    private static final UUID ATTACHMENT_ID = UUID.fromString("aaaaaaaa-1111-4111-8111-111111111111");
    private static final UUID COMPLAINT_ID = UUID.fromString("bbbbbbbb-2222-4222-8222-222222222222");

    @Autowired
    private MockMvc mvc;

    @MockitoBean
    private AttachmentLinkService attachmentLinks;

    @MockitoBean
    private ComplaintService complaints;

    @Test
    void unauthenticatedDownloadReturns401() throws Exception {
        mvc.perform(get("/api/v1/attachments/{id}/content", ATTACHMENT_ID))
            .andExpect(status().isUnauthorized())
            .andExpect(jsonPath("$.code").value("UNAUTHENTICATED"));
    }

    @Test
    void authorizedUserReceivesBytesWithNoSniffHeader() throws Exception {
        AttachmentRecord record = new AttachmentRecord(
            ATTACHMENT_ID, COMPLAINT_ID, null, "REPORT",
            "ab/cd/11111111-2222-4333-8444-555555555555.png", "image/png", 4, Instant.now());
        when(attachmentLinks.requireMetadata(ATTACHMENT_ID)).thenReturn(record);
        when(attachmentLinks.loadBytesOrMissing(record)).thenReturn(new byte[] {1, 2, 3, 4});

        mvc.perform(get("/api/v1/attachments/{id}/content", ATTACHMENT_ID)
                .with(jwt().jwt(t -> t.subject(CALLER_ID.toString()).claim("role", "STUDENT"))))
            .andExpect(status().isOk())
            .andExpect(content().contentType(MediaType.IMAGE_PNG))
            .andExpect(header().string("X-Content-Type-Options", "nosniff"))
            .andExpect(content().bytes(new byte[] {1, 2, 3, 4}));
    }

    @Test
    void forbiddenUserIsBlockedFromSensitiveAttachment() throws Exception {
        AttachmentRecord record = new AttachmentRecord(
            ATTACHMENT_ID, COMPLAINT_ID, null, "REPORT",
            "ab/cd/11111111-2222-4333-8444-555555555555.png", "image/png", 4, Instant.now());
        when(attachmentLinks.requireMetadata(ATTACHMENT_ID)).thenReturn(record);
        doThrow(ApiException.forbidden("FORBIDDEN", "You do not have access to this attachment."))
            .when(complaints).requireAttachmentAccess(CALLER_ID, COMPLAINT_ID);

        mvc.perform(get("/api/v1/attachments/{id}/content", ATTACHMENT_ID)
                .with(jwt().jwt(t -> t.subject(CALLER_ID.toString()).claim("role", "STUDENT"))))
            .andExpect(status().isForbidden())
            .andExpect(jsonPath("$.code").value("FORBIDDEN"));
    }
}
