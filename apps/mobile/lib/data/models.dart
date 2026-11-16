import 'package:flutter/material.dart';

enum UserRole {
  student('STUDENT', 'Student'),
  staff('STAFF', 'Staff'),
  supervisor('SUPERVISOR', 'Supervisor'),
  admin('ADMIN', 'Admin');

  const UserRole(this.apiValue, this.label);
  final String apiValue;
  final String label;

  bool get isStaffOrAbove => this != UserRole.student;

  static UserRole fromApi(String? raw) {
    return UserRole.values.firstWhere(
      (role) => role.apiValue == raw?.toUpperCase(),
      orElse: () => UserRole.student,
    );
  }
}

enum ComplaintSeverity {
  low('LOW', 'Low', 'A minor inconvenience'),
  medium('MEDIUM', 'Medium', 'Affects normal use'),
  high('HIGH', 'High', 'Blocks normal use'),
  critical('CRITICAL', 'Critical', 'Needs urgent attention');

  const ComplaintSeverity(this.apiValue, this.label, this.description);
  final String apiValue;
  final String label;
  final String description;

  static ComplaintSeverity fromApi(String? raw) {
    return ComplaintSeverity.values.firstWhere(
      (s) => s.apiValue == raw?.toUpperCase(),
      orElse: () => ComplaintSeverity.medium,
    );
  }
}

enum ComplaintStatus {
  reported('REPORTED', 'Received', Icons.inbox_outlined),
  assigned('ASSIGNED', 'Assigned', Icons.group_outlined),
  inProgress('IN_PROGRESS', 'In progress', Icons.build_outlined),
  resolved('RESOLVED', 'Fixed, please check', Icons.task_alt_rounded),
  verified('VERIFIED', 'Closed', Icons.check_circle_outline_rounded),
  reopened('REOPENED', 'Reopened', Icons.replay_rounded),
  rejected('REJECTED', 'Not accepted', Icons.block_rounded);

  const ComplaintStatus(this.apiValue, this.label, this.icon);
  final String apiValue;
  final String label;
  final IconData icon;

  bool get isOpen =>
      this != ComplaintStatus.resolved &&
      this != ComplaintStatus.verified &&
      this != ComplaintStatus.rejected;

  static ComplaintStatus fromApi(String? raw) {
    return ComplaintStatus.values.firstWhere(
      (s) => s.apiValue == raw?.toUpperCase(),
      orElse: () => ComplaintStatus.reported,
    );
  }
}

class UserAccount {
  const UserAccount({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    this.departmentId,
    this.scopeLocationId,
    this.emailVerified = false,
    this.mustChangePassword = false,
  });

  final String id;
  final String email;
  final String fullName;
  final UserRole role;
  final String? departmentId;
  final String? scopeLocationId;
  final bool emailVerified;
  final bool mustChangePassword;

  factory UserAccount.fromJson(Map<String, dynamic> json) {
    return UserAccount(
      id: _asString(json['id']),
      email: _asString(json['email']),
      fullName: _asString(json['fullName']),
      role: UserRole.fromApi(_asNullableString(json['role'])),
      departmentId: _asNullableString(json['departmentId']),
      scopeLocationId: _asNullableString(json['scopeLocationId']),
      emailVerified: json['emailVerified'] == true,
      mustChangePassword: json['mustChangePassword'] == true,
    );
  }
}

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresInSeconds,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresInSeconds;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      accessToken: _asString(json['accessToken']),
      refreshToken: _asString(json['refreshToken']),
      expiresInSeconds: _asInt(json['expiresInSeconds'], fallback: 900),
    );
  }
}

class CategoryModel {
  const CategoryModel({
    required this.id,
    required this.name,
    required this.theme,
    required this.defaultSeverity,
    required this.photoPolicy,
    required this.isSensitive,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final String theme;
  final ComplaintSeverity defaultSeverity;
  final String photoPolicy; // OPTIONAL | REQUIRED | DISABLED
  final bool isSensitive;
  final int sortOrder;

  IconData get icon {
    final lower = name.toLowerCase();
    if (lower.contains('plumb') || lower.contains('water')) return Icons.water_drop_outlined;
    if (lower.contains('electr') || lower.contains('power') || lower.contains('light')) {
      return Icons.bolt_outlined;
    }
    if (lower.contains('wi-fi') || lower.contains('network') || lower.contains('it') || lower.contains('portal')) {
      return Icons.wifi_rounded;
    }
    if (lower.contains('mess') || lower.contains('food') || lower.contains('dining')) {
      return Icons.restaurant_outlined;
    }
    if (lower.contains('clean') || lower.contains('housekeeping') || lower.contains('waste')) {
      return Icons.cleaning_services_outlined;
    }
    if (lower.contains('ac') || lower.contains('hvac') || lower.contains('cooling')) {
      return Icons.ac_unit_rounded;
    }
    if (lower.contains('carpent') || lower.contains('furniture') || lower.contains('door')) {
      return Icons.carpenter_outlined;
    }
    if (lower.contains('security') || lower.contains('cctv') || lower.contains('gate')) {
      return Icons.shield_outlined;
    }
    if (isSensitive || lower.contains('harass') || lower.contains('welfare') || lower.contains('grievance')) {
      return Icons.lock_outline_rounded;
    }
    if (lower.contains('hostel') || lower.contains('room')) return Icons.bed_outlined;
    if (lower.contains('academic') || lower.contains('class') || lower.contains('lab')) {
      return Icons.school_outlined;
    }
    return Icons.build_circle_outlined;
  }

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: _asString(json['id']),
      name: _asString(json['name']),
      theme: _asString(json['theme'], fallback: 'OTHER'),
      defaultSeverity: ComplaintSeverity.fromApi(_asNullableString(json['defaultSeverity'])),
      photoPolicy: _asString(json['photoPolicy'], fallback: 'OPTIONAL'),
      isSensitive: json['isSensitive'] == true,
      sortOrder: _asInt(json['sortOrder']),
    );
  }
}

class LocationModel {
  const LocationModel({
    required this.id,
    required this.parentId,
    required this.type,
    required this.name,
    required this.path,
  });

  final String id;
  final String? parentId;
  final String type;
  final String name;
  final String path;

  factory LocationModel.fromJson(Map<String, dynamic> json) {
    return LocationModel(
      id: _asString(json['id']),
      parentId: _asNullableString(json['parentId']),
      type: _asString(json['type']),
      name: _asString(json['name']),
      path: _asString(json['path']),
    );
  }
}

class DepartmentModel {
  const DepartmentModel({
    required this.id,
    required this.name,
    required this.code,
    required this.kind,
    this.headUserId,
  });

  final String id;
  final String name;
  final String code;
  final String kind;
  final String? headUserId;

  bool get isRestricted => kind == 'RESTRICTED';

  factory DepartmentModel.fromJson(Map<String, dynamic> json) {
    return DepartmentModel(
      id: _asString(json['id']),
      name: _asString(json['name']),
      code: _asString(json['code']),
      kind: _asString(json['kind'], fallback: 'SERVICE'),
      headUserId: _asNullableString(json['headUserId']),
    );
  }
}

class StaffMemberModel {
  const StaffMemberModel({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    this.departmentId,
    this.departmentName,
    this.scopeLocationId,
  });

  final String id;
  final String fullName;
  final String email;
  final UserRole role;
  final String? departmentId;
  final String? departmentName;
  final String? scopeLocationId;

  factory StaffMemberModel.fromJson(Map<String, dynamic> json) {
    return StaffMemberModel(
      id: _asString(json['id']),
      fullName: _asString(json['fullName']),
      email: _asString(json['email']),
      role: UserRole.fromApi(_asNullableString(json['role'])),
      departmentId: _asNullableString(json['departmentId']),
      departmentName: _asNullableString(json['departmentName']),
      scopeLocationId: _asNullableString(json['scopeLocationId']),
    );
  }
}

class ReporterSummary {
  const ReporterSummary({required this.id, required this.fullName, required this.email});
  final String id;
  final String fullName;
  final String email;

  factory ReporterSummary.fromJson(Map<String, dynamic> json) {
    return ReporterSummary(
      id: _asString(json['id']),
      fullName: _asString(json['fullName']),
      email: _asString(json['email']),
    );
  }
}

class AttachmentMetadata {
  const AttachmentMetadata({
    required this.id,
    this.eventId,
    required this.kind,
    required this.storageKey,
    required this.mimeType,
    required this.sizeBytes,
    required this.createdAt,
  });

  final String id;
  final int? eventId;
  final String kind;
  final String storageKey;
  final String mimeType;
  final int sizeBytes;
  final DateTime createdAt;

  factory AttachmentMetadata.fromJson(Map<String, dynamic> json) {
    return AttachmentMetadata(
      id: _asString(json['id']),
      eventId: json['eventId'] is num ? (json['eventId'] as num).toInt() : null,
      kind: _asString(json['kind'], fallback: 'REPORT'),
      storageKey: _asString(json['storageKey']),
      mimeType: _asString(json['mimeType'], fallback: 'image/jpeg'),
      sizeBytes: _asInt(json['sizeBytes']),
      createdAt: _asDateTime(json['createdAt']) ?? DateTime.now(),
    );
  }
}

class UploadedAttachment {
  const UploadedAttachment({
    required this.storageKey,
    required this.mimeType,
    required this.sizeBytes,
    required this.checksumSha256,
  });

  final String storageKey;
  final String mimeType;
  final int sizeBytes;
  final String checksumSha256;

  factory UploadedAttachment.fromJson(Map<String, dynamic> json) {
    return UploadedAttachment(
      storageKey: _asString(json['storageKey']),
      mimeType: _asString(json['mimeType']),
      sizeBytes: _asInt(json['sizeBytes']),
      checksumSha256: _asString(json['checksumSha256']),
    );
  }
}

class ComplaintEvent {
  const ComplaintEvent({
    required this.id,
    required this.actorRole,
    this.actorName,
    required this.eventType,
    this.fromStatus,
    this.toStatus,
    required this.payload,
    required this.createdAt,
  });

  final int id;
  final String actorRole;
  final String? actorName;
  final String eventType;
  final String? fromStatus;
  final String? toStatus;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  String? get note => _asNullableString(payload['note']);

  factory ComplaintEvent.fromJson(Map<String, dynamic> json) {
    return ComplaintEvent(
      id: _asInt(json['id']),
      actorRole: _asString(json['actorRole'], fallback: 'SYSTEM'),
      actorName: _asNullableString(json['actorName']),
      eventType: _asString(json['eventType']),
      fromStatus: _asNullableString(json['fromStatus']),
      toStatus: _asNullableString(json['toStatus']),
      payload: json['payload'] is Map<String, dynamic>
          ? json['payload'] as Map<String, dynamic>
          : const <String, dynamic>{},
      createdAt: _asDateTime(json['createdAt']) ?? DateTime.now(),
    );
  }
}

class ComplaintSummary {
  const ComplaintSummary({
    required this.id,
    required this.code,
    required this.title,
    this.description,
    required this.severity,
    required this.status,
    required this.categoryId,
    required this.categoryName,
    required this.categoryTheme,
    required this.isSensitive,
    required this.photoPolicy,
    required this.locationId,
    required this.locationName,
    required this.locationPath,
    this.departmentId,
    this.departmentName,
    this.departmentCode,
    this.assignedTo,
    this.assigneeName,
    this.slaDueAt,
    required this.escalationLevel,
    required this.reopenCount,
    required this.version,
    required this.isMine,
    this.reporter,
    required this.createdAt,
    required this.updatedAt,
    this.resolvedAt,
    this.verifiedAt,
  });

  final String id;
  final String code;
  final String title;
  final String? description;
  final ComplaintSeverity severity;
  final ComplaintStatus status;
  final String categoryId;
  final String categoryName;
  final String categoryTheme;
  final bool isSensitive;
  final String photoPolicy;
  final String locationId;
  final String locationName;
  final String locationPath;
  final String? departmentId;
  final String? departmentName;
  final String? departmentCode;
  final String? assignedTo;
  final String? assigneeName;
  final DateTime? slaDueAt;
  final int escalationLevel;
  final int reopenCount;
  final int version;
  final bool isMine;
  final ReporterSummary? reporter;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? resolvedAt;
  final DateTime? verifiedAt;

  bool get isOverdue =>
      slaDueAt != null && status.isOpen && slaDueAt!.isBefore(DateTime.now().toUtc());

  factory ComplaintSummary.fromJson(Map<String, dynamic> json) {
    return ComplaintSummary(
      id: _asString(json['id']),
      code: _asString(json['code']),
      title: _asString(json['title']),
      description: _asNullableString(json['description']),
      severity: ComplaintSeverity.fromApi(_asNullableString(json['severity'])),
      status: ComplaintStatus.fromApi(_asNullableString(json['status'])),
      categoryId: _asString(json['categoryId']),
      categoryName: _asString(json['categoryName']),
      categoryTheme: _asString(json['categoryTheme'], fallback: 'OTHER'),
      isSensitive: json['isSensitive'] == true,
      photoPolicy: _asString(json['photoPolicy'], fallback: 'OPTIONAL'),
      locationId: _asString(json['locationId']),
      locationName: _asString(json['locationName']),
      locationPath: _asString(json['locationPath']),
      departmentId: _asNullableString(json['departmentId']),
      departmentName: _asNullableString(json['departmentName']),
      departmentCode: _asNullableString(json['departmentCode']),
      assignedTo: _asNullableString(json['assignedTo']),
      assigneeName: _asNullableString(json['assigneeName']),
      slaDueAt: _asDateTime(json['slaDueAt']),
      escalationLevel: _asInt(json['escalationLevel']),
      reopenCount: _asInt(json['reopenCount']),
      version: _asInt(json['version']),
      isMine: json['isMine'] == true,
      reporter: json['reporter'] is Map<String, dynamic>
          ? ReporterSummary.fromJson(json['reporter'] as Map<String, dynamic>)
          : null,
      createdAt: _asDateTime(json['createdAt']) ?? DateTime.now(),
      updatedAt: _asDateTime(json['updatedAt']) ?? DateTime.now(),
      resolvedAt: _asDateTime(json['resolvedAt']),
      verifiedAt: _asDateTime(json['verifiedAt']),
    );
  }
}

class ComplaintDetail extends ComplaintSummary {
  const ComplaintDetail({
    required super.id,
    required super.code,
    required super.title,
    super.description,
    required super.severity,
    required super.status,
    required super.categoryId,
    required super.categoryName,
    required super.categoryTheme,
    required super.isSensitive,
    required super.photoPolicy,
    required super.locationId,
    required super.locationName,
    required super.locationPath,
    super.departmentId,
    super.departmentName,
    super.departmentCode,
    super.assignedTo,
    super.assigneeName,
    super.slaDueAt,
    required super.escalationLevel,
    required super.reopenCount,
    required super.version,
    required super.isMine,
    super.reporter,
    required super.createdAt,
    required super.updatedAt,
    super.resolvedAt,
    super.verifiedAt,
    required this.events,
    required this.attachments,
  });

  final List<ComplaintEvent> events;
  final List<AttachmentMetadata> attachments;

  factory ComplaintDetail.fromJson(Map<String, dynamic> json) {
    final summary = ComplaintSummary.fromJson(json);
    final rawEvents = json['events'] is List<dynamic> ? json['events'] as List<dynamic> : const <dynamic>[];
    final rawAttachments =
        json['attachments'] is List<dynamic> ? json['attachments'] as List<dynamic> : const <dynamic>[];
    return ComplaintDetail(
      id: summary.id,
      code: summary.code,
      title: summary.title,
      description: summary.description,
      severity: summary.severity,
      status: summary.status,
      categoryId: summary.categoryId,
      categoryName: summary.categoryName,
      categoryTheme: summary.categoryTheme,
      isSensitive: summary.isSensitive,
      photoPolicy: summary.photoPolicy,
      locationId: summary.locationId,
      locationName: summary.locationName,
      locationPath: summary.locationPath,
      departmentId: summary.departmentId,
      departmentName: summary.departmentName,
      departmentCode: summary.departmentCode,
      assignedTo: summary.assignedTo,
      assigneeName: summary.assigneeName,
      slaDueAt: summary.slaDueAt,
      escalationLevel: summary.escalationLevel,
      reopenCount: summary.reopenCount,
      version: summary.version,
      isMine: summary.isMine,
      reporter: summary.reporter,
      createdAt: summary.createdAt,
      updatedAt: summary.updatedAt,
      resolvedAt: summary.resolvedAt,
      verifiedAt: summary.verifiedAt,
      events: rawEvents
          .whereType<Map<String, dynamic>>()
          .map(ComplaintEvent.fromJson)
          .toList(),
      attachments: rawAttachments
          .whereType<Map<String, dynamic>>()
          .map(AttachmentMetadata.fromJson)
          .toList(),
    );
  }
}

class ComplaintPage {
  const ComplaintPage({
    required this.items,
    required this.page,
    required this.size,
    required this.totalElements,
    required this.totalPages,
  });

  final List<ComplaintSummary> items;
  final int page;
  final int size;
  final int totalElements;
  final int totalPages;

  factory ComplaintPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] is List<dynamic> ? json['items'] as List<dynamic> : const <dynamic>[];
    return ComplaintPage(
      items: rawItems.whereType<Map<String, dynamic>>().map(ComplaintSummary.fromJson).toList(),
      page: _asInt(json['page']),
      size: _asInt(json['size'], fallback: 20),
      totalElements: _asInt(json['totalElements']),
      totalPages: _asInt(json['totalPages']),
    );
  }
}

class SimilarComplaints {
  const SimilarComplaints({
    required this.count,
    this.mostCommonStatus,
    required this.byStatus,
  });

  final int count;
  final String? mostCommonStatus;
  final Map<String, int> byStatus;

  factory SimilarComplaints.fromJson(Map<String, dynamic> json) {
    final rawMap = json['byStatus'] is Map<String, dynamic>
        ? json['byStatus'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return SimilarComplaints(
      count: _asInt(json['count']),
      mostCommonStatus: _asNullableString(json['mostCommonStatus']),
      byStatus: rawMap.map((k, v) => MapEntry(k, _asInt(v))),
    );
  }
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.message,
    this.complaintId,
    required this.status,
    required this.createdAt,
    this.readAt,
  });

  final String id;
  final String type;
  final String message;
  final String? complaintId;
  final String status;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: _asString(json['id']),
      type: _asString(json['type']),
      message: _asString(json['message']),
      complaintId: _asNullableString(json['complaintId']),
      status: _asString(json['status'], fallback: 'SENT'),
      createdAt: _asDateTime(json['createdAt']) ?? DateTime.now(),
      readAt: _asDateTime(json['readAt']),
    );
  }
}

class NotificationList {
  const NotificationList({required this.unreadCount, required this.items});
  final int unreadCount;
  final List<AppNotification> items;

  factory NotificationList.fromJson(Map<String, dynamic> json) {
    final raw = json['items'] is List<dynamic> ? json['items'] as List<dynamic> : const <dynamic>[];
    return NotificationList(
      unreadCount: _asInt(json['unreadCount']),
      items: raw.whereType<Map<String, dynamic>>().map(AppNotification.fromJson).toList(),
    );
  }
}

class StatusCount {
  const StatusCount({required this.status, required this.count});
  final String status;
  final int count;

  factory StatusCount.fromJson(Map<String, dynamic> json) =>
      StatusCount(status: _asString(json['status']), count: _asInt(json['count']));
}

class DepartmentCount {
  const DepartmentCount({
    required this.departmentId,
    required this.departmentCode,
    required this.departmentName,
    required this.openCount,
  });

  final String departmentId;
  final String departmentCode;
  final String departmentName;
  final int openCount;

  factory DepartmentCount.fromJson(Map<String, dynamic> json) => DepartmentCount(
        departmentId: _asString(json['departmentId']),
        departmentCode: _asString(json['departmentCode']),
        departmentName: _asString(json['departmentName']),
        openCount: _asInt(json['openCount']),
      );
}

class DailyCreatedCount {
  const DailyCreatedCount({required this.day, required this.count});
  final String day;
  final int count;

  factory DailyCreatedCount.fromJson(Map<String, dynamic> json) =>
      DailyCreatedCount(day: _asString(json['day']), count: _asInt(json['count']));
}

class AnalyticsSummary {
  const AnalyticsSummary({
    required this.totalComplaints,
    required this.openCount,
    required this.inProgressCount,
    required this.awaitingVerificationCount,
    required this.verifiedCount,
    required this.rejectedCount,
    required this.overdueCount,
    required this.byStatus,
    required this.byDepartment,
    required this.createdPerDay,
  });

  final int totalComplaints;
  final int openCount;
  final int inProgressCount;
  final int awaitingVerificationCount;
  final int verifiedCount;
  final int rejectedCount;
  final int overdueCount;
  final List<StatusCount> byStatus;
  final List<DepartmentCount> byDepartment;
  final List<DailyCreatedCount> createdPerDay;

  factory AnalyticsSummary.fromJson(Map<String, dynamic> json) {
    final rawStatus =
        json['byStatus'] is List<dynamic> ? json['byStatus'] as List<dynamic> : const <dynamic>[];
    final rawDept = json['byDepartment'] is List<dynamic>
        ? json['byDepartment'] as List<dynamic>
        : const <dynamic>[];
    final rawDaily = json['createdPerDay'] is List<dynamic>
        ? json['createdPerDay'] as List<dynamic>
        : const <dynamic>[];
    return AnalyticsSummary(
      totalComplaints: _asInt(json['totalComplaints']),
      openCount: _asInt(json['openCount']),
      inProgressCount: _asInt(json['inProgressCount']),
      awaitingVerificationCount: _asInt(json['awaitingVerificationCount']),
      verifiedCount: _asInt(json['verifiedCount']),
      rejectedCount: _asInt(json['rejectedCount']),
      overdueCount: _asInt(json['overdueCount']),
      byStatus: rawStatus.whereType<Map<String, dynamic>>().map(StatusCount.fromJson).toList(),
      byDepartment:
          rawDept.whereType<Map<String, dynamic>>().map(DepartmentCount.fromJson).toList(),
      createdPerDay:
          rawDaily.whereType<Map<String, dynamic>>().map(DailyCreatedCount.fromJson).toList(),
    );
  }
}

class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
    this.details = const <String, String>{},
    this.traceId,
  });

  final int statusCode;
  final String code;
  final String message;
  final Map<String, String> details;
  final String? traceId;

  bool get isNetworkError => statusCode == 0;
  bool get isMissingFile => code == 'ATTACHMENT_FILE_MISSING';
  bool get isConflict => statusCode == 409;
  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => 'ApiException($statusCode, $code): $message';
}

String _asString(Object? value, {String fallback = ''}) =>
    value is String ? value : (value?.toString() ?? fallback);

String? _asNullableString(Object? value) {
  if (value == null) return null;
  final str = value.toString();
  return str.isEmpty ? null : str;
}

int _asInt(Object? value, {int fallback = 0}) => value is num ? value.toInt() : fallback;

DateTime? _asDateTime(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}
