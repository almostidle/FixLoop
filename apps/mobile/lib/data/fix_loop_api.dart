import 'dart:typed_data';

import 'models.dart';

/// Backend REST contract so widget tests can substitute an in-memory fake.
abstract interface class FixLoopApi {
  void setSessionExpiredHandler(void Function()? handler);

  Future<AuthSession> login({required String email, required String password});

  Future<UserAccount> register({
    required String email,
    required String password,
    required String fullName,
  });

  Future<void> logout();

  Future<UserAccount> me();

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  Future<List<CategoryModel>> listCategories();

  Future<List<LocationModel>> listLocations({String? parentId});

  Future<List<DepartmentModel>> listDepartments();

  Future<List<StaffMemberModel>> listStaff({String? departmentId});

  Future<ComplaintPage> listComplaints({
    String? status,
    String? departmentId,
    bool? mine,
    bool? assignedToMe,
    bool? unclaimed,
    bool? overdue,
    String? q,
    String? sort,
    int page = 0,
    int size = 20,
  });

  Future<SimilarComplaints> findSimilar({
    required String locationId,
    required String categoryId,
  });

  Future<ComplaintDetail> getComplaint(String id);

  Future<ComplaintDetail> createComplaint({
    required String categoryId,
    required String locationId,
    required String title,
    String? description,
    ComplaintSeverity? severity,
    List<String> attachmentKeys = const <String>[],
    String? idempotencyKey,
  });

  Future<ComplaintDetail> transitionComplaint(
    String id, {
    required String toStatus,
    required int version,
    String? note,
    String? departmentId,
    String? assignedTo,
    List<String> attachmentKeys = const <String>[],
  });

  Future<ComplaintDetail> addNote(String id, String note);

  Future<UploadedAttachment> uploadAttachment({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  });

  Future<Uint8List> fetchAttachmentBytes(String attachmentId);

  Future<NotificationList> listNotifications();

  Future<AppNotification> markNotificationRead(String id);

  Future<AnalyticsSummary> getAnalyticsSummary();
}
