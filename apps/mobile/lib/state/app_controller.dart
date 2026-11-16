import 'package:flutter/foundation.dart';

import '../data/fix_loop_api.dart';
import '../data/models.dart';

/// Holds authenticated user session, reference catalogs, notifications, and error state.
class AppController extends ChangeNotifier {
  AppController({required this.api}) {
    api.setSessionExpiredHandler(_handleSessionExpired);
  }

  final FixLoopApi api;

  UserAccount? _currentUser;
  bool _busy = false;
  String? _bannerError;

  List<CategoryModel> _categories = const <CategoryModel>[];
  List<LocationModel> _locations = const <LocationModel>[];
  List<DepartmentModel> _departments = const <DepartmentModel>[];
  NotificationList? _notifications;
  AnalyticsSummary? _analytics;

  UserAccount? get currentUser => _currentUser;
  bool get isSignedIn => _currentUser != null;
  bool get isBusy => _busy;
  String? get bannerError => _bannerError;

  List<CategoryModel> get categories => _categories;
  List<LocationModel> get locations => _locations;
  List<DepartmentModel> get departments => _departments;
  NotificationList? get notifications => _notifications;
  AnalyticsSummary? get analytics => _analytics;
  int get unreadNotificationCount => _notifications?.unreadCount ?? 0;

  void clearBanner() {
    if (_bannerError != null) {
      _bannerError = null;
      notifyListeners();
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    _busy = true;
    _bannerError = null;
    notifyListeners();
    try {
      await api.login(email: email, password: password);
      _currentUser = await api.me();
      await loadInitialData();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> registerAndSignIn({
    required String email,
    required String password,
    required String fullName,
  }) async {
    _busy = true;
    _bannerError = null;
    notifyListeners();
    try {
      await api.register(email: email, password: password, fullName: fullName);
      await api.login(email: email, password: password);
      _currentUser = await api.me();
      await loadInitialData();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> loadInitialData() async {
    if (_currentUser == null) return;
    try {
      final results = await Future.wait<Object?>(<Future<Object?>>[
        api.listCategories(),
        api.listLocations(),
        api.listDepartments(),
        api.listNotifications(),
        api.getAnalyticsSummary(),
      ]);
      _categories = results[0]! as List<CategoryModel>;
      _locations = results[1]! as List<LocationModel>;
      _departments = results[2]! as List<DepartmentModel>;
      _notifications = results[3]! as NotificationList;
      _analytics = results[4]! as AnalyticsSummary;
      _bannerError = null;
    } on ApiException catch (e) {
      _bannerError = e.message;
    }
    notifyListeners();
  }

  Future<void> refreshNotifications() async {
    if (_currentUser == null) return;
    try {
      _notifications = await api.listNotifications();
      _bannerError = null;
      notifyListeners();
    } on ApiException catch (e) {
      _bannerError = e.message;
      notifyListeners();
    }
  }

  Future<void> markNotificationRead(String id) async {
    try {
      final updated = await api.markNotificationRead(id);
      final current = _notifications;
      if (current != null) {
        final items = current.items.map((item) => item.id == id ? updated : item).toList();
        final unread = items.where((item) => item.isUnread).length;
        _notifications = NotificationList(unreadCount: unread, items: items);
        notifyListeners();
      }
    } on ApiException catch (e) {
      _bannerError = e.message;
      notifyListeners();
    }
  }

  Future<void> refreshAnalytics() async {
    if (_currentUser == null) return;
    try {
      _analytics = await api.getAnalyticsSummary();
      notifyListeners();
    } on ApiException catch (e) {
      _bannerError = e.message;
      notifyListeners();
    }
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await api.changePassword(currentPassword: currentPassword, newPassword: newPassword);
    // Changing password revokes all refresh tokens on the server; sign cleanly back in or sign out.
    await signOut(message: 'Password updated. Please sign in with your new password.');
  }

  Future<void> signOut({String? message}) async {
    await api.logout();
    _currentUser = null;
    _categories = const <CategoryModel>[];
    _locations = const <LocationModel>[];
    _departments = const <DepartmentModel>[];
    _notifications = null;
    _analytics = null;
    _bannerError = message;
    notifyListeners();
  }

  void _handleSessionExpired() {
    _currentUser = null;
    _categories = const <CategoryModel>[];
    _locations = const <LocationModel>[];
    _departments = const <DepartmentModel>[];
    _notifications = null;
    _analytics = null;
    _bannerError = 'Your session expired. Please sign in again.';
    notifyListeners();
  }

  @override
  void dispose() {
    api.setSessionExpiredHandler(null);
    super.dispose();
  }
}
