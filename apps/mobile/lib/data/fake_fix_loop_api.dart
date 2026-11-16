import 'dart:convert';
import 'dart:typed_data';

import 'fix_loop_api.dart';
import 'models.dart';

/// Deterministic in-memory backend for offline widget tests.
class FakeFixLoopApi implements FixLoopApi {
  FakeFixLoopApi({
    String? initialEmail,
    this.missingAttachmentIds = const <String>{},
  }) {
    _seedData();
    if (initialEmail != null) {
      _activeUser = _usersByEmail[initialEmail];
    }
  }

  final Set<String> missingAttachmentIds;
  void Function()? _onSessionExpired;
  UserAccount? _activeUser;
  int _nextCode = 27;
  int _nextEventId = 100;
  int _nextUploadId = 1;

  final Map<String, UserAccount> _usersByEmail = <String, UserAccount>{};
  final Map<String, String> _passwordsByEmail = <String, String>{};
  final List<CategoryModel> _categories = <CategoryModel>[];
  final List<LocationModel> _locations = <LocationModel>[];
  final List<DepartmentModel> _departments = <DepartmentModel>[];
  final List<StaffMemberModel> _staff = <StaffMemberModel>[];
  final Map<String, ComplaintDetail> _complaints = <String, ComplaintDetail>{};
  final Map<String, String> _idempotencyToId = <String, String>{};
  final Map<String, Uint8List> _uploadedBytesByKey = <String, Uint8List>{};
  final Map<String, Uint8List> _attachmentBytesById = <String, Uint8List>{};
  final List<AppNotification> _notifications = <AppNotification>[];

  static final Uint8List samplePng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP43+DwHwAHAAK/K9fH4gAAAABJRU5ErkJggg==',
  );

  void _seedData() {
    const facId = 'dept-fac';
    const itId = 'dept-it';
    const iccId = 'dept-icc';

    _departments.addAll(const <DepartmentModel>[
      DepartmentModel(id: facId, name: 'Facilities & Maintenance', code: 'FAC', kind: 'SERVICE', headUserId: 'sup-fac'),
      DepartmentModel(id: itId, name: 'IT & Network Services', code: 'IT', kind: 'SERVICE', headUserId: 'sup-it'),
      DepartmentModel(id: iccId, name: 'Internal Complaints Committee', code: 'ICC', kind: 'RESTRICTED', headUserId: 'sup-icc'),
    ]);

    const locCampus = 'loc-campus';
    const locHostel = 'loc-hostel-t1';
    const locFloor2 = 'loc-floor-2';
    const locRoom204 = 'loc-room-204';
    const locMainGate = 'loc-main-gate';

    _locations.addAll(const <LocationModel>[
      LocationModel(id: locCampus, parentId: null, type: 'CAMPUS', name: 'BML Munjal Campus', path: '/bmu'),
      LocationModel(id: locMainGate, parentId: locCampus, type: 'AREA', name: 'Main Gate', path: '/bmu/main-gate'),
      LocationModel(id: locHostel, parentId: locCampus, type: 'BLOCK', name: 'Boys Hostel T1', path: '/bmu/boys-hostel-t1'),
      LocationModel(id: locFloor2, parentId: locHostel, type: 'FLOOR', name: 'Floor 2', path: '/bmu/boys-hostel-t1/floor-2'),
      LocationModel(id: locRoom204, parentId: locFloor2, type: 'ROOM', name: 'Room 204', path: '/bmu/boys-hostel-t1/floor-2/room-204'),
    ]);

    _categories.addAll(const <CategoryModel>[
      CategoryModel(id: 'cat-wifi', name: 'Wi-Fi & Network', theme: 'IT', defaultSeverity: ComplaintSeverity.high, photoPolicy: 'OPTIONAL', isSensitive: false, sortOrder: 1),
      CategoryModel(id: 'cat-plumbing', name: 'Plumbing & Water', theme: 'INFRASTRUCTURE', defaultSeverity: ComplaintSeverity.high, photoPolicy: 'REQUIRED', isSensitive: false, sortOrder: 2),
      CategoryModel(id: 'cat-ac', name: 'AC & Cooling', theme: 'INFRASTRUCTURE', defaultSeverity: ComplaintSeverity.medium, photoPolicy: 'OPTIONAL', isSensitive: false, sortOrder: 3),
      CategoryModel(id: 'cat-sensitive', name: 'Harassment & Sensitive Grievance', theme: 'WELFARE', defaultSeverity: ComplaintSeverity.critical, photoPolicy: 'DISABLED', isSensitive: true, sortOrder: 4),
    ]);

    const student1 = UserAccount(id: 'stu-1', email: 'student1@bmu.edu.in', fullName: 'Aarav Mehta', role: UserRole.student, emailVerified: true);
    const student2 = UserAccount(id: 'stu-2', email: 'student2@bmu.edu.in', fullName: 'Priya Sharma', role: UserRole.student, emailVerified: true);
    const staffFac = UserAccount(id: 'staff-fac', email: 'tech.fac@bmu.edu.in', fullName: 'Ramesh Kumar', role: UserRole.staff, departmentId: facId, emailVerified: true);
    const supFac = UserAccount(id: 'sup-fac', email: 'head.fac@bmu.edu.in', fullName: 'Anil Kapoor', role: UserRole.supervisor, departmentId: facId, scopeLocationId: locCampus, emailVerified: true);
    const admin = UserAccount(id: 'admin-1', email: 'admin@bmu.edu.in', fullName: 'Campus Admin', role: UserRole.admin, emailVerified: true);

    for (final u in <UserAccount>[student1, student2, staffFac, supFac, admin]) {
      _usersByEmail[u.email] = u;
      _passwordsByEmail[u.email] = 'campus-lamp-2026';
    }

    _staff.addAll(const <StaffMemberModel>[
      StaffMemberModel(id: 'staff-fac', fullName: 'Ramesh Kumar', email: 'tech.fac@bmu.edu.in', role: UserRole.staff, departmentId: facId, departmentName: 'Facilities & Maintenance'),
      StaffMemberModel(id: 'sup-fac', fullName: 'Anil Kapoor', email: 'head.fac@bmu.edu.in', role: UserRole.supervisor, departmentId: facId, departmentName: 'Facilities & Maintenance'),
    ]);

    final now = DateTime.now().toUtc();
    _complaints['cmp-1'] = ComplaintDetail(
      id: 'cmp-1',
      code: 'FL-2026-000024',
      title: 'Wi-Fi keeps dropping in Room 204',
      description: 'Access point disconnects every 10 minutes.',
      severity: ComplaintSeverity.high,
      status: ComplaintStatus.resolved,
      categoryId: 'cat-wifi',
      categoryName: 'Wi-Fi & Network',
      categoryTheme: 'IT',
      isSensitive: false,
      photoPolicy: 'OPTIONAL',
      locationId: locRoom204,
      locationName: 'Room 204',
      locationPath: '/bmu/boys-hostel-t1/floor-2/room-204',
      departmentId: itId,
      departmentName: 'IT & Network Services',
      departmentCode: 'IT',
      assignedTo: 'staff-fac',
      assigneeName: 'Ramesh Kumar',
      slaDueAt: now.add(const Duration(hours: 4)),
      escalationLevel: 0,
      reopenCount: 0,
      version: 3,
      isMine: true,
      reporter: const ReporterSummary(id: 'stu-1', fullName: 'Aarav Mehta', email: 'student1@bmu.edu.in'),
      createdAt: now.subtract(const Duration(hours: 6)),
      updatedAt: now.subtract(const Duration(minutes: 30)),
      resolvedAt: now.subtract(const Duration(minutes: 30)),
      events: <ComplaintEvent>[
        ComplaintEvent(
          id: 1,
          actorRole: 'STUDENT',
          actorName: 'Aarav Mehta',
          eventType: 'CREATED',
          toStatus: 'REPORTED',
          payload: const <String, dynamic>{},
          createdAt: now.subtract(const Duration(hours: 6)),
        ),
        ComplaintEvent(
          id: 2,
          actorRole: 'STAFF',
          actorName: 'Ramesh Kumar',
          eventType: 'RESOLVED',
          fromStatus: 'IN_PROGRESS',
          toStatus: 'RESOLVED',
          payload: const <String, dynamic>{'note': 'Replaced ceiling access point firmware.'},
          createdAt: now.subtract(const Duration(minutes: 30)),
        ),
      ],
      attachments: <AttachmentMetadata>[
        AttachmentMetadata(
          id: 'att-seeded-1',
          kind: 'REPORT',
          storageKey: 'complaints/2026/10/seeded.jpg',
          mimeType: 'image/jpeg',
          sizeBytes: 1200,
          createdAt: now.subtract(const Duration(hours: 6)),
        ),
      ],
    );

    _complaints['cmp-2'] = ComplaintDetail(
      id: 'cmp-2',
      code: 'FL-2026-000025',
      title: 'Streetlight flickering at Main Gate',
      description: 'Entrance pole flickers at night.',
      severity: ComplaintSeverity.medium,
      status: ComplaintStatus.assigned,
      categoryId: 'cat-ac',
      categoryName: 'AC & Cooling',
      categoryTheme: 'INFRASTRUCTURE',
      isSensitive: false,
      photoPolicy: 'OPTIONAL',
      locationId: locMainGate,
      locationName: 'Main Gate',
      locationPath: '/bmu/main-gate',
      departmentId: facId,
      departmentName: 'Facilities & Maintenance',
      departmentCode: 'FAC',
      slaDueAt: now.add(const Duration(hours: 12)),
      escalationLevel: 0,
      reopenCount: 0,
      version: 1,
      isMine: false,
      createdAt: now.subtract(const Duration(hours: 3)),
      updatedAt: now.subtract(const Duration(hours: 3)),
      events: <ComplaintEvent>[
        ComplaintEvent(
          id: 3,
          actorRole: 'STUDENT',
          eventType: 'CREATED',
          toStatus: 'REPORTED',
          payload: const <String, dynamic>{},
          createdAt: now.subtract(const Duration(hours: 3)),
        ),
      ],
      attachments: const <AttachmentMetadata>[],
    );

    _notifications.add(AppNotification(
      id: 'notif-1',
      type: 'COMPLAINT_RESOLVED',
      message: 'Issue FL-2026-000024 was marked resolved. Please verify the fix.',
      complaintId: 'cmp-1',
      status: 'SENT',
      createdAt: now.subtract(const Duration(minutes: 30)),
    ));
  }

  UserAccount _requireUser() {
    final user = _activeUser;
    if (user == null) {
      throw const ApiException(
        statusCode: 401,
        code: 'UNAUTHENTICATED',
        message: 'Authentication is required.',
      );
    }
    return user;
  }

  @override
  void setSessionExpiredHandler(void Function()? handler) {
    _onSessionExpired = handler;
  }

  @override
  Future<AuthSession> login({required String email, required String password}) async {
    final normalized = email.trim().toLowerCase();
    final user = _usersByEmail[normalized];
    if (user == null || _passwordsByEmail[normalized] != password) {
      throw const ApiException(
        statusCode: 401,
        code: 'INVALID_CREDENTIALS',
        message: 'Email or password is incorrect.',
      );
    }
    _activeUser = user;
    return const AuthSession(accessToken: 'fake-jwt', refreshToken: 'fake-refresh', expiresInSeconds: 900);
  }

  @override
  Future<UserAccount> register({
    required String email,
    required String password,
    required String fullName,
  }) async {
    final normalized = email.trim().toLowerCase();
    if (!normalized.endsWith('@bmu.edu.in')) {
      throw const ApiException(
        statusCode: 400,
        code: 'EMAIL_DOMAIN_NOT_ALLOWED',
        message: 'Only university email addresses (@bmu.edu.in) can register.',
      );
    }
    if (_usersByEmail.containsKey(normalized)) {
      throw const ApiException(
        statusCode: 409,
        code: 'EMAIL_ALREADY_REGISTERED',
        message: 'An account with this email already exists.',
      );
    }
    final user = UserAccount(
      id: 'stu-${_usersByEmail.length + 1}',
      email: normalized,
      fullName: fullName.trim(),
      role: UserRole.student,
    );
    _usersByEmail[normalized] = user;
    _passwordsByEmail[normalized] = password;
    return user;
  }

  @override
  Future<void> logout() async {
    _activeUser = null;
  }

  @override
  Future<UserAccount> me() async => _requireUser();

  @override
  Future<void> changePassword({required String currentPassword, required String newPassword}) async {
    final user = _requireUser();
    if (_passwordsByEmail[user.email] != currentPassword) {
      throw const ApiException(
        statusCode: 400,
        code: 'INVALID_CURRENT_PASSWORD',
        message: 'Current password is incorrect.',
      );
    }
    _passwordsByEmail[user.email] = newPassword;
  }

  @override
  Future<List<CategoryModel>> listCategories() async {
    _requireUser();
    return List<CategoryModel>.from(_categories);
  }

  @override
  Future<List<LocationModel>> listLocations({String? parentId}) async {
    _requireUser();
    if (parentId == null) return List<LocationModel>.from(_locations);
    return _locations.where((l) => l.parentId == parentId).toList();
  }

  @override
  Future<List<DepartmentModel>> listDepartments() async {
    final user = _requireUser();
    if (user.role == UserRole.admin || user.role == UserRole.supervisor) {
      return List<DepartmentModel>.from(_departments);
    }
    return _departments
        .where((d) => !d.isRestricted || d.id == user.departmentId)
        .toList();
  }

  @override
  Future<List<StaffMemberModel>> listStaff({String? departmentId}) async {
    final user = _requireUser();
    if (user.role != UserRole.supervisor && user.role != UserRole.admin) {
      throw const ApiException(statusCode: 403, code: 'FORBIDDEN', message: 'Forbidden');
    }
    if (departmentId == null) return List<StaffMemberModel>.from(_staff);
    return _staff.where((s) => s.departmentId == departmentId).toList();
  }

  @override
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
  }) async {
    final user = _requireUser();
    var items = _complaints.values.where((c) {
      final isMine = c.reporter?.id == user.id || c.isMine && user.id == 'stu-1';
      if (c.isSensitive &&
          user.role != UserRole.admin &&
          !isMine &&
          user.departmentId != c.departmentId) {
        return false;
      }
      if (mine == true && !isMine) return false;
      if (assignedToMe == true && c.assignedTo != user.id) return false;
      if (unclaimed == true && (c.assignedTo != null || !c.status.isOpen)) return false;
      if (overdue == true && !c.isOverdue) return false;
      if (departmentId != null && c.departmentId != departmentId) return false;
      if (status != null && status.isNotEmpty) {
        final allowed = status.split(',').map((s) => s.trim()).toSet();
        if (!allowed.contains(c.status.apiValue)) return false;
      }
      if (q != null && q.trim().isNotEmpty) {
        final query = q.trim().toLowerCase();
        if (!c.title.toLowerCase().contains(query) &&
            !c.code.toLowerCase().contains(query) &&
            !c.locationName.toLowerCase().contains(query)) {
          return false;
        }
      }
      return true;
    }).map((c) => _scopeComplaint(c, user)).toList();

    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final start = (page * size).clamp(0, items.length);
    final end = (start + size).clamp(0, items.length);
    final totalPages = (items.length + size - 1) ~/ size;
    return ComplaintPage(
      items: items.sublist(start, end),
      page: page,
      size: size,
      totalElements: items.length,
      totalPages: totalPages,
    );
  }

  @override
  Future<SimilarComplaints> findSimilar({required String locationId, required String categoryId}) async {
    _requireUser();
    final matches = _complaints.values
        .where((c) => !c.isSensitive && c.locationId == locationId && c.categoryId == categoryId && c.status.isOpen)
        .toList();
    final byStatus = <String, int>{};
    for (final m in matches) {
      byStatus[m.status.apiValue] = (byStatus[m.status.apiValue] ?? 0) + 1;
    }
    return SimilarComplaints(
      count: matches.length,
      mostCommonStatus: byStatus.isEmpty ? null : byStatus.keys.first,
      byStatus: byStatus,
    );
  }

  @override
  Future<ComplaintDetail> getComplaint(String id) async {
    final user = _requireUser();
    final c = _complaints[id];
    if (c == null) {
      throw const ApiException(statusCode: 404, code: 'COMPLAINT_NOT_FOUND', message: 'Complaint not found.');
    }
    return _scopeComplaint(c, user);
  }

  @override
  Future<ComplaintDetail> createComplaint({
    required String categoryId,
    required String locationId,
    required String title,
    String? description,
    ComplaintSeverity? severity,
    List<String> attachmentKeys = const <String>[],
    String? idempotencyKey,
  }) async {
    final user = _requireUser();
    if (idempotencyKey != null && _idempotencyToId.containsKey('${user.id}:$idempotencyKey')) {
      return _scopeComplaint(_complaints[_idempotencyToId['${user.id}:$idempotencyKey']!]!, user);
    }
    final cat = _categories.firstWhere((c) => c.id == categoryId);
    final loc = _locations.firstWhere((l) => l.id == locationId);
    if (cat.photoPolicy == 'REQUIRED' && attachmentKeys.isEmpty) {
      throw const ApiException(
        statusCode: 422,
        code: 'PHOTO_REQUIRED',
        message: 'This category requires at least one photograph.',
      );
    }
    if (cat.photoPolicy == 'DISABLED' && attachmentKeys.isNotEmpty) {
      throw const ApiException(
        statusCode: 422,
        code: 'PHOTO_NOT_ALLOWED',
        message: 'Photographs are disabled for this category.',
      );
    }
    final dept = cat.isSensitive
        ? _departments.firstWhere((d) => d.code == 'ICC')
        : (cat.theme == 'IT'
            ? _departments.firstWhere((d) => d.code == 'IT')
            : _departments.firstWhere((d) => d.code == 'FAC'));
    final now = DateTime.now().toUtc();
    final id = 'cmp-${_nextCode}';
    final code = 'FL-2026-${_nextCode.toString().padLeft(6, '0')}';
    _nextCode++;

    final attachments = <AttachmentMetadata>[];
    for (final key in attachmentKeys) {
      final attId = 'att-${attachments.length + 1}-$id';
      final bytes = _uploadedBytesByKey[key] ?? samplePng;
      _attachmentBytesById[attId] = bytes;
      attachments.add(AttachmentMetadata(
        id: attId,
        kind: 'REPORT',
        storageKey: key,
        mimeType: 'image/png',
        sizeBytes: bytes.length,
        createdAt: now,
      ));
    }

    final detail = ComplaintDetail(
      id: id,
      code: code,
      title: title.trim(),
      description: description?.trim(),
      severity: severity ?? cat.defaultSeverity,
      status: ComplaintStatus.assigned,
      categoryId: cat.id,
      categoryName: cat.name,
      categoryTheme: cat.theme,
      isSensitive: cat.isSensitive,
      photoPolicy: cat.photoPolicy,
      locationId: loc.id,
      locationName: loc.name,
      locationPath: loc.path,
      departmentId: dept.id,
      departmentName: dept.name,
      departmentCode: dept.code,
      slaDueAt: now.add(const Duration(hours: 12)),
      escalationLevel: 0,
      reopenCount: 0,
      version: 1,
      isMine: true,
      reporter: ReporterSummary(id: user.id, fullName: user.fullName, email: user.email),
      createdAt: now,
      updatedAt: now,
      events: <ComplaintEvent>[
        ComplaintEvent(
          id: _nextEventId++,
          actorRole: user.role.apiValue,
          actorName: user.fullName,
          eventType: 'CREATED',
          toStatus: 'REPORTED',
          payload: const <String, dynamic>{},
          createdAt: now,
        ),
        ComplaintEvent(
          id: _nextEventId++,
          actorRole: 'SYSTEM',
          eventType: 'ROUTED',
          fromStatus: 'REPORTED',
          toStatus: 'ASSIGNED',
          payload: <String, dynamic>{'department': dept.code},
          createdAt: now,
        ),
      ],
      attachments: attachments,
    );
    _complaints[id] = detail;
    if (idempotencyKey != null) {
      _idempotencyToId['${user.id}:$idempotencyKey'] = id;
    }
    return _scopeComplaint(detail, user);
  }

  @override
  Future<ComplaintDetail> transitionComplaint(
    String id, {
    required String toStatus,
    required int version,
    String? note,
    String? departmentId,
    String? assignedTo,
    List<String> attachmentKeys = const <String>[],
  }) async {
    final user = _requireUser();
    final existing = _complaints[id];
    if (existing == null) {
      throw const ApiException(statusCode: 404, code: 'COMPLAINT_NOT_FOUND', message: 'Complaint not found.');
    }
    if (existing.version != version) {
      throw const ApiException(statusCode: 409, code: 'VERSION_CONFLICT', message: 'Conflict; refresh.');
    }
    final target = ComplaintStatus.fromApi(toStatus);
    final now = DateTime.now().toUtc();
    var nextStatus = target;
    var nextDeptId = departmentId ?? existing.departmentId;
    var nextDeptName = existing.departmentName;
    var nextDeptCode = existing.departmentCode;
    var nextAssignedTo = existing.assignedTo;
    var nextAssigneeName = existing.assigneeName;
    var reopenCount = existing.reopenCount;
    var resolvedAt = existing.resolvedAt;
    var verifiedAt = existing.verifiedAt;
    var versionNext = existing.version + 1;

    final events = List<ComplaintEvent>.from(existing.events);
    if (target == ComplaintStatus.inProgress) {
      nextAssignedTo = user.id;
      nextAssigneeName = user.fullName;
      events.add(ComplaintEvent(
        id: _nextEventId++,
        actorRole: user.role.apiValue,
        actorName: user.fullName,
        eventType: 'CLAIMED',
        fromStatus: existing.status.apiValue,
        toStatus: 'IN_PROGRESS',
        payload: <String, dynamic>{if (note != null) 'note': note},
        createdAt: now,
      ));
    } else if (target == ComplaintStatus.resolved) {
      resolvedAt = now;
      events.add(ComplaintEvent(
        id: _nextEventId++,
        actorRole: user.role.apiValue,
        actorName: user.fullName,
        eventType: 'RESOLVED',
        fromStatus: existing.status.apiValue,
        toStatus: 'RESOLVED',
        payload: <String, dynamic>{if (note != null) 'note': note},
        createdAt: now,
      ));
    } else if (target == ComplaintStatus.verified) {
      verifiedAt = now;
      events.add(ComplaintEvent(
        id: _nextEventId++,
        actorRole: user.role.apiValue,
        actorName: user.fullName,
        eventType: 'VERIFIED',
        fromStatus: existing.status.apiValue,
        toStatus: 'VERIFIED',
        payload: <String, dynamic>{if (note != null) 'note': note},
        createdAt: now,
      ));
    } else if (target == ComplaintStatus.reopened) {
      reopenCount++;
      nextStatus = ComplaintStatus.assigned;
      nextAssignedTo = null;
      nextAssigneeName = null;
      resolvedAt = null;
      versionNext++;
      events.add(ComplaintEvent(
        id: _nextEventId++,
        actorRole: user.role.apiValue,
        actorName: user.fullName,
        eventType: 'REOPENED',
        fromStatus: 'RESOLVED',
        toStatus: 'REOPENED',
        payload: <String, dynamic>{'note': note ?? '', 'reopen_count': reopenCount},
        createdAt: now,
      ));
      events.add(ComplaintEvent(
        id: _nextEventId++,
        actorRole: 'SYSTEM',
        eventType: 'ROUTED',
        fromStatus: 'REOPENED',
        toStatus: 'ASSIGNED',
        payload: <String, dynamic>{'department': nextDeptCode ?? 'FAC'},
        createdAt: now,
      ));
    } else if (target == ComplaintStatus.assigned) {
      if (departmentId != null) {
        final d = _departments.firstWhere((dept) => dept.id == departmentId);
        nextDeptId = d.id;
        nextDeptName = d.name;
        nextDeptCode = d.code;
      }
      if (assignedTo != null) {
        final member = _staff.firstWhere((s) => s.id == assignedTo);
        nextAssignedTo = member.id;
        nextAssigneeName = member.fullName;
      } else {
        nextAssignedTo = null;
        nextAssigneeName = null;
      }
      events.add(ComplaintEvent(
        id: _nextEventId++,
        actorRole: user.role.apiValue,
        actorName: user.fullName,
        eventType: existing.status == ComplaintStatus.inProgress ? 'RELEASED' : 'REASSIGNED',
        fromStatus: existing.status.apiValue,
        toStatus: 'ASSIGNED',
        payload: <String, dynamic>{if (note != null) 'note': note},
        createdAt: now,
      ));
    } else {
      events.add(ComplaintEvent(
        id: _nextEventId++,
        actorRole: user.role.apiValue,
        actorName: user.fullName,
        eventType: target.apiValue,
        fromStatus: existing.status.apiValue,
        toStatus: target.apiValue,
        payload: <String, dynamic>{if (note != null) 'note': note},
        createdAt: now,
      ));
    }

    final updated = ComplaintDetail(
      id: existing.id,
      code: existing.code,
      title: existing.title,
      description: existing.description,
      severity: existing.severity,
      status: nextStatus,
      categoryId: existing.categoryId,
      categoryName: existing.categoryName,
      categoryTheme: existing.categoryTheme,
      isSensitive: existing.isSensitive,
      photoPolicy: existing.photoPolicy,
      locationId: existing.locationId,
      locationName: existing.locationName,
      locationPath: existing.locationPath,
      departmentId: nextDeptId,
      departmentName: nextDeptName,
      departmentCode: nextDeptCode,
      assignedTo: nextAssignedTo,
      assigneeName: nextAssigneeName,
      slaDueAt: existing.slaDueAt,
      escalationLevel: existing.escalationLevel,
      reopenCount: reopenCount,
      version: versionNext,
      isMine: existing.isMine,
      reporter: existing.reporter,
      createdAt: existing.createdAt,
      updatedAt: now,
      resolvedAt: resolvedAt,
      verifiedAt: verifiedAt,
      events: events,
      attachments: existing.attachments,
    );
    _complaints[id] = updated;
    return _scopeComplaint(updated, user);
  }

  @override
  Future<ComplaintDetail> addNote(String id, String note) async {
    final user = _requireUser();
    final existing = _complaints[id]!;
    final now = DateTime.now().toUtc();
    final events = List<ComplaintEvent>.from(existing.events)
      ..add(ComplaintEvent(
        id: _nextEventId++,
        actorRole: user.role.apiValue,
        actorName: user.fullName,
        eventType: 'NOTE',
        fromStatus: existing.status.apiValue,
        toStatus: existing.status.apiValue,
        payload: <String, dynamic>{'note': note.trim()},
        createdAt: now,
      ));
    final updated = ComplaintDetail(
      id: existing.id,
      code: existing.code,
      title: existing.title,
      description: existing.description,
      severity: existing.severity,
      status: existing.status,
      categoryId: existing.categoryId,
      categoryName: existing.categoryName,
      categoryTheme: existing.categoryTheme,
      isSensitive: existing.isSensitive,
      photoPolicy: existing.photoPolicy,
      locationId: existing.locationId,
      locationName: existing.locationName,
      locationPath: existing.locationPath,
      departmentId: existing.departmentId,
      departmentName: existing.departmentName,
      departmentCode: existing.departmentCode,
      assignedTo: existing.assignedTo,
      assigneeName: existing.assigneeName,
      slaDueAt: existing.slaDueAt,
      escalationLevel: existing.escalationLevel,
      reopenCount: existing.reopenCount,
      version: existing.version,
      isMine: existing.isMine,
      reporter: existing.reporter,
      createdAt: existing.createdAt,
      updatedAt: now,
      resolvedAt: existing.resolvedAt,
      verifiedAt: existing.verifiedAt,
      events: events,
      attachments: existing.attachments,
    );
    _complaints[id] = updated;
    return _scopeComplaint(updated, user);
  }

  @override
  Future<UploadedAttachment> uploadAttachment({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  }) async {
    _requireUser();
    final key = 'ab/cd/11111111-2222-4333-8444-${_nextUploadId.toString().padLeft(12, '0')}.png';
    _nextUploadId++;
    _uploadedBytesByKey[key] = bytes;
    return UploadedAttachment(
      storageKey: key,
      mimeType: mimeType,
      sizeBytes: bytes.length,
      checksumSha256: 'a' * 64,
    );
  }

  @override
  Future<Uint8List> fetchAttachmentBytes(String attachmentId) async {
    _requireUser();
    if (missingAttachmentIds.contains(attachmentId)) {
      throw const ApiException(
        statusCode: 404,
        code: 'ATTACHMENT_FILE_MISSING',
        message: 'The attachment file is not present on storage.',
      );
    }
    return _attachmentBytesById[attachmentId] ?? samplePng;
  }

  @override
  Future<NotificationList> listNotifications() async {
    _requireUser();
    final unread = _notifications.where((n) => n.isUnread).length;
    return NotificationList(unreadCount: unread, items: List<AppNotification>.from(_notifications));
  }

  @override
  Future<AppNotification> markNotificationRead(String id) async {
    _requireUser();
    final idx = _notifications.indexWhere((n) => n.id == id);
    final old = _notifications[idx];
    final updated = AppNotification(
      id: old.id,
      type: old.type,
      message: old.message,
      complaintId: old.complaintId,
      status: old.status,
      createdAt: old.createdAt,
      readAt: DateTime.now().toUtc(),
    );
    _notifications[idx] = updated;
    return updated;
  }

  @override
  Future<AnalyticsSummary> getAnalyticsSummary() async {
    final user = _requireUser();
    final all = _complaints.values.toList();
    final openCount = all.where((c) => c.status.isOpen).length;
    final inProg = all.where((c) => c.status == ComplaintStatus.inProgress).length;
    final resolved = all.where((c) => c.status == ComplaintStatus.resolved).length;
    final verified = all.where((c) => c.status == ComplaintStatus.verified).length;
    final rejected = all.where((c) => c.status == ComplaintStatus.rejected).length;
    return AnalyticsSummary(
      totalComplaints: all.length,
      openCount: openCount,
      inProgressCount: inProg,
      awaitingVerificationCount: resolved,
      verifiedCount: verified,
      rejectedCount: rejected,
      overdueCount: all.where((c) => c.isOverdue).length,
      byStatus: <StatusCount>[
        for (final s in ComplaintStatus.values)
          if (all.any((c) => c.status == s))
            StatusCount(status: s.apiValue, count: all.where((c) => c.status == s).length),
      ],
      byDepartment: user.role == UserRole.student
          ? const <DepartmentCount>[]
          : <DepartmentCount>[
              for (final d in _departments)
                if (user.role == UserRole.admin || !d.isRestricted || d.id == user.departmentId)
                  DepartmentCount(
                    departmentId: d.id,
                    departmentCode: d.code,
                    departmentName: d.name,
                    openCount: all.where((c) => c.departmentId == d.id && c.status.isOpen).length,
                  ),
            ],
      createdPerDay: user.role == UserRole.student
          ? const <DailyCreatedCount>[]
          : <DailyCreatedCount>[DailyCreatedCount(day: '2026-11-16', count: all.length)],
    );
  }

  ComplaintDetail _scopeComplaint(ComplaintDetail c, UserAccount caller) {
    final isMine = c.reporter?.id == caller.id || (c.id == 'cmp-1' && caller.id == 'stu-1');
    final showReporter = caller.role == UserRole.admin || isMine;
    return ComplaintDetail(
      id: c.id,
      code: c.code,
      title: c.title,
      description: c.description,
      severity: c.severity,
      status: c.status,
      categoryId: c.categoryId,
      categoryName: c.categoryName,
      categoryTheme: c.categoryTheme,
      isSensitive: c.isSensitive,
      photoPolicy: c.photoPolicy,
      locationId: c.locationId,
      locationName: c.locationName,
      locationPath: c.locationPath,
      departmentId: c.departmentId,
      departmentName: c.departmentName,
      departmentCode: c.departmentCode,
      assignedTo: c.assignedTo,
      assigneeName: c.assigneeName,
      slaDueAt: c.slaDueAt,
      escalationLevel: c.escalationLevel,
      reopenCount: c.reopenCount,
      version: c.version,
      isMine: isMine,
      reporter: showReporter ? c.reporter : null,
      createdAt: c.createdAt,
      updatedAt: c.updatedAt,
      resolvedAt: c.resolvedAt,
      verifiedAt: c.verifiedAt,
      events: c.events,
      attachments: c.attachments,
    );
  }

  void triggerSessionExpired() => _onSessionExpired?.call();
}
