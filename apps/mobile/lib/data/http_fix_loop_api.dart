import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as http_parser;

import 'fix_loop_api.dart';
import 'models.dart';

const String defaultApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8080',
);

/// Live REST client targeting the Spring Boot FixLoop API with silent token refresh.
class HttpFixLoopApi implements FixLoopApi {
  HttpFixLoopApi({
    String baseUrl = defaultApiBaseUrl,
    http.Client? client,
  })  : _baseUrl = _trimTrailingSlash(baseUrl),
        _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

  String? _accessToken;
  String? _refreshToken;
  Future<bool>? _refreshInFlight;
  void Function()? _onSessionExpired;

  @override
  void setSessionExpiredHandler(void Function()? handler) {
    _onSessionExpired = handler;
  }

  static String _trimTrailingSlash(String raw) {
    var trimmed = raw.trim();
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed.isEmpty ? 'http://localhost:8080' : trimmed;
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final uri = Uri.parse('$_baseUrl$path');
    if (query == null || query.isEmpty) return uri;
    return uri.replace(queryParameters: query);
  }

  @override
  Future<AuthSession> login({required String email, required String password}) async {
    final response = await _rawSend(
      () => _client.post(
        _uri('/api/v1/auth/login'),
        headers: _jsonHeaders(authenticated: false),
        body: jsonEncode(<String, String>{'email': email.trim(), 'password': password}),
      ),
    );
    final map = _decodeObject(response);
    final session = AuthSession.fromJson(map);
    _accessToken = session.accessToken;
    _refreshToken = session.refreshToken;
    return session;
  }

  @override
  Future<UserAccount> register({
    required String email,
    required String password,
    required String fullName,
  }) async {
    final response = await _rawSend(
      () => _client.post(
        _uri('/api/v1/auth/register'),
        headers: _jsonHeaders(authenticated: false),
        body: jsonEncode(<String, String>{
          'email': email.trim(),
          'password': password,
          'fullName': fullName.trim(),
        }),
      ),
    );
    return UserAccount.fromJson(_decodeObject(response));
  }

  @override
  Future<void> logout() async {
    final refresh = _refreshToken;
    _accessToken = null;
    _refreshToken = null;
    if (refresh == null || refresh.isEmpty) return;
    try {
      await _client.post(
        _uri('/api/v1/auth/logout'),
        headers: _jsonHeaders(authenticated: false),
        body: jsonEncode(<String, String>{'refreshToken': refresh}),
      );
    } catch (_) {
      // Logout clears client state regardless of transient network failure.
    }
  }

  @override
  Future<UserAccount> me() async {
    final response = await _sendWithRefresh(
      () => _client.get(_uri('/api/v1/me'), headers: _jsonHeaders()),
    );
    return UserAccount.fromJson(_decodeObject(response));
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final response = await _sendWithRefresh(
      () => _client.post(
        _uri('/api/v1/auth/change-password'),
        headers: _jsonHeaders(),
        body: jsonEncode(<String, String>{
          'currentPassword': currentPassword,
          'newPassword': newPassword,
        }),
      ),
    );
    _ensureSuccess(response);
  }

  @override
  Future<List<CategoryModel>> listCategories() async {
    final response = await _sendWithRefresh(
      () => _client.get(_uri('/api/v1/categories'), headers: _jsonHeaders()),
    );
    return _decodeList(response).map(CategoryModel.fromJson).toList();
  }

  @override
  Future<List<LocationModel>> listLocations({String? parentId}) async {
    final query = parentId == null ? null : <String, String>{'parentId': parentId};
    final response = await _sendWithRefresh(
      () => _client.get(_uri('/api/v1/locations', query), headers: _jsonHeaders()),
    );
    return _decodeList(response).map(LocationModel.fromJson).toList();
  }

  @override
  Future<List<DepartmentModel>> listDepartments() async {
    final response = await _sendWithRefresh(
      () => _client.get(_uri('/api/v1/departments'), headers: _jsonHeaders()),
    );
    return _decodeList(response).map(DepartmentModel.fromJson).toList();
  }

  @override
  Future<List<StaffMemberModel>> listStaff({String? departmentId}) async {
    final query = departmentId == null ? null : <String, String>{'departmentId': departmentId};
    final response = await _sendWithRefresh(
      () => _client.get(_uri('/api/v1/users/staff', query), headers: _jsonHeaders()),
    );
    return _decodeList(response).map(StaffMemberModel.fromJson).toList();
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
    final query = <String, String>{
      'page': page.toString(),
      'size': size.toString(),
      if (status != null && status.isNotEmpty) 'status': status,
      if (departmentId != null && departmentId.isNotEmpty) 'departmentId': departmentId,
      if (mine != null) 'mine': mine.toString(),
      if (assignedToMe != null) 'assignedToMe': assignedToMe.toString(),
      if (unclaimed != null) 'unclaimed': unclaimed.toString(),
      if (overdue != null) 'overdue': overdue.toString(),
      if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
      if (sort != null && sort.isNotEmpty) 'sort': sort,
    };
    final response = await _sendWithRefresh(
      () => _client.get(_uri('/api/v1/complaints', query), headers: _jsonHeaders()),
    );
    return ComplaintPage.fromJson(_decodeObject(response));
  }

  @override
  Future<SimilarComplaints> findSimilar({
    required String locationId,
    required String categoryId,
  }) async {
    final response = await _sendWithRefresh(
      () => _client.get(
        _uri('/api/v1/complaints/similar', <String, String>{
          'locationId': locationId,
          'categoryId': categoryId,
        }),
        headers: _jsonHeaders(),
      ),
    );
    return SimilarComplaints.fromJson(_decodeObject(response));
  }

  @override
  Future<ComplaintDetail> getComplaint(String id) async {
    final response = await _sendWithRefresh(
      () => _client.get(_uri('/api/v1/complaints/$id'), headers: _jsonHeaders()),
    );
    return ComplaintDetail.fromJson(_decodeObject(response));
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
    final headers = _jsonHeaders();
    if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
      headers['Idempotency-Key'] = idempotencyKey;
    }
    final payload = <String, dynamic>{
      'categoryId': categoryId,
      'locationId': locationId,
      'title': title.trim(),
      if (description != null && description.trim().isNotEmpty) 'description': description.trim(),
      if (severity != null) 'severity': severity.apiValue,
      if (attachmentKeys.isNotEmpty) 'attachmentKeys': attachmentKeys,
    };
    final response = await _sendWithRefresh(
      () => _client.post(_uri('/api/v1/complaints'), headers: headers, body: jsonEncode(payload)),
    );
    return ComplaintDetail.fromJson(_decodeObject(response));
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
    final payload = <String, dynamic>{
      'toStatus': toStatus,
      'version': version,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      if (departmentId != null && departmentId.isNotEmpty) 'departmentId': departmentId,
      if (assignedTo != null && assignedTo.isNotEmpty) 'assignedTo': assignedTo,
      if (attachmentKeys.isNotEmpty) 'attachmentKeys': attachmentKeys,
    };
    final response = await _sendWithRefresh(
      () => _client.post(
        _uri('/api/v1/complaints/$id/transition'),
        headers: _jsonHeaders(),
        body: jsonEncode(payload),
      ),
    );
    return ComplaintDetail.fromJson(_decodeObject(response));
  }

  @override
  Future<ComplaintDetail> addNote(String id, String note) async {
    final response = await _sendWithRefresh(
      () => _client.post(
        _uri('/api/v1/complaints/$id/notes'),
        headers: _jsonHeaders(),
        body: jsonEncode(<String, String>{'note': note.trim()}),
      ),
    );
    return ComplaintDetail.fromJson(_decodeObject(response));
  }

  @override
  Future<UploadedAttachment> uploadAttachment({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  }) async {
    final response = await _sendMultipartWithRefresh(bytes: bytes, filename: filename, mimeType: mimeType);
    return UploadedAttachment.fromJson(_decodeObject(response));
  }

  @override
  Future<Uint8List> fetchAttachmentBytes(String attachmentId) async {
    final response = await _sendWithRefresh(
      () => _client.get(
        _uri('/api/v1/attachments/$attachmentId/content'),
        headers: _authOnlyHeaders(),
      ),
    );
    _ensureSuccess(response);
    return response.bodyBytes;
  }

  @override
  Future<NotificationList> listNotifications() async {
    final response = await _sendWithRefresh(
      () => _client.get(_uri('/api/v1/notifications'), headers: _jsonHeaders()),
    );
    return NotificationList.fromJson(_decodeObject(response));
  }

  @override
  Future<AppNotification> markNotificationRead(String id) async {
    final response = await _sendWithRefresh(
      () => _client.post(_uri('/api/v1/notifications/$id/read'), headers: _jsonHeaders()),
    );
    return AppNotification.fromJson(_decodeObject(response));
  }

  @override
  Future<AnalyticsSummary> getAnalyticsSummary() async {
    final response = await _sendWithRefresh(
      () => _client.get(_uri('/api/v1/analytics/summary'), headers: _jsonHeaders()),
    );
    return AnalyticsSummary.fromJson(_decodeObject(response));
  }

  Map<String, String> _jsonHeaders({bool authenticated = true}) => <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (authenticated && _accessToken != null) 'Authorization': 'Bearer $_accessToken',
      };

  Map<String, String> _authOnlyHeaders() => <String, String>{
        if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
      };

  Future<http.Response> _rawSend(Future<http.Response> Function() request) async {
    try {
      return await request();
    } catch (_) {
      throw const ApiException(
        statusCode: 0,
        code: 'NETWORK_ERROR',
        message: 'Could not reach the FixLoop server. Check that the backend is running.',
      );
    }
  }

  Future<http.Response> _sendWithRefresh(Future<http.Response> Function() request) async {
    var response = await _rawSend(request);
    if (response.statusCode == 401 && _refreshToken != null) {
      final refreshed = await _refreshSession();
      if (refreshed) {
        response = await _rawSend(request);
      } else {
        _onSessionExpired?.call();
      }
    }
    return response;
  }

  Future<http.Response> _sendMultipartWithRefresh({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  }) async {
    Future<http.Response> sendOnce() async {
      final req = http.MultipartRequest('POST', _uri('/api/v1/attachments'));
      if (_accessToken != null) {
        req.headers['Authorization'] = 'Bearer $_accessToken';
      }
      final parts = mimeType.split('/');
      final mediaType = parts.length == 2
          ? http_parser.MediaType(parts[0], parts[1])
          : http_parser.MediaType('image', 'jpeg');
      req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename, contentType: mediaType));
      try {
        final streamed = await _client.send(req);
        return await http.Response.fromStream(streamed);
      } catch (_) {
        throw const ApiException(
          statusCode: 0,
          code: 'NETWORK_ERROR',
          message: 'Could not reach the FixLoop server during upload.',
        );
      }
    }

    var response = await sendOnce();
    if (response.statusCode == 401 && _refreshToken != null) {
      final refreshed = await _refreshSession();
      if (refreshed) {
        response = await sendOnce();
      } else {
        _onSessionExpired?.call();
      }
    }
    return response;
  }

  Future<bool> _refreshSession() async {
    final existing = _refreshInFlight;
    if (existing != null) return existing;

    final completer = Completer<bool>();
    _refreshInFlight = completer.future;
    try {
      final refresh = _refreshToken;
      if (refresh == null || refresh.isEmpty) {
        completer.complete(false);
        return false;
      }
      final response = await _client.post(
        _uri('/api/v1/auth/refresh'),
        headers: _jsonHeaders(authenticated: false),
        body: jsonEncode(<String, String>{'refreshToken': refresh}),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final session = AuthSession.fromJson(decoded);
          _accessToken = session.accessToken;
          _refreshToken = session.refreshToken;
          completer.complete(true);
          return true;
        }
      }
      _accessToken = null;
      _refreshToken = null;
      completer.complete(false);
      return false;
    } catch (_) {
      completer.complete(false);
      return false;
    } finally {
      _refreshInFlight = null;
    }
  }

  void _ensureSuccess(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    throw _parseError(response);
  }

  Map<String, dynamic> _decodeObject(http.Response response) {
    _ensureSuccess(response);
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw ApiException(
      statusCode: response.statusCode,
      code: 'INVALID_RESPONSE',
      message: 'Unexpected response format from server.',
    );
  }

  List<Map<String, dynamic>> _decodeList(http.Response response) {
    _ensureSuccess(response);
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is List<dynamic>) {
      return decoded.whereType<Map<String, dynamic>>().toList();
    }
    throw ApiException(
      statusCode: response.statusCode,
      code: 'INVALID_RESPONSE',
      message: 'Unexpected list response format from server.',
    );
  }

  ApiException _parseError(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        final rawDetails = decoded['details'];
        final details = <String, String>{};
        if (rawDetails is Map<String, dynamic>) {
          rawDetails.forEach((key, value) {
            details[key] = value?.toString() ?? '';
          });
        }
        return ApiException(
          statusCode: response.statusCode,
          code: decoded['code']?.toString() ?? 'HTTP_${response.statusCode}',
          message: decoded['message']?.toString() ?? 'Request failed (${response.statusCode}).',
          details: details,
          traceId: decoded['traceId']?.toString(),
        );
      }
    } catch (_) {
      // Non-JSON error body
    }
    return ApiException(
      statusCode: response.statusCode,
      code: 'HTTP_${response.statusCode}',
      message: 'Request failed with status ${response.statusCode}.',
    );
  }
}
