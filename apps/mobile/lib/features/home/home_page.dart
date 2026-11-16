import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../design/widgets.dart';
import '../../preview/photo_picker.dart';
import '../../state/app_controller.dart';
import '../issues/issue_detail_page.dart';
import '../report/report_flow_page.dart';

enum _QueueFilter { mine, campus, assignedToMe, unclaimed, needsTriage, overdue, allDept }

/// Role-aware Campus Home / Operations Console connected to the live FixLoop API.
class CampusHomePage extends StatefulWidget {
  const CampusHomePage({
    required this.controller,
    required this.photoPicker,
    super.key,
  });

  final AppController controller;
  final PreviewPhotoPicker photoPicker;

  @override
  State<CampusHomePage> createState() => _CampusHomePageState();
}

class _CampusHomePageState extends State<CampusHomePage> {
  final TextEditingController _searchController = TextEditingController();

  int _tabIndex = 0;
  bool _searching = false;
  late _QueueFilter _queueFilter;
  ComplaintStatus? _statusFilter;
  String? _departmentFilter;

  List<ComplaintSummary> _complaints = const <ComplaintSummary>[];
  int _page = 0;
  int _totalPages = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  UserAccount get _user => widget.controller.currentUser!;
  bool get _isStaffOrAbove => _user.role.isStaffOrAbove;

  @override
  void initState() {
    super.initState();
    _queueFilter = switch (_user.role) {
      UserRole.student => _QueueFilter.mine,
      UserRole.staff => _QueueFilter.assignedToMe,
      UserRole.supervisor || UserRole.admin => _QueueFilter.needsTriage,
    };
    _loadComplaints(reset: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadComplaints({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _page = 0;
      });
    } else {
      if (_loadingMore || _page + 1 >= _totalPages) return;
      setState(() => _loadingMore = true);
    }

    final nextPage = reset ? 0 : _page + 1;
    try {
      String? statusParam = _statusFilter?.apiValue;
      bool? mine;
      bool? assignedToMe;
      bool? unclaimed;
      bool? overdue;

      switch (_queueFilter) {
        case _QueueFilter.mine:
          mine = true;
        case _QueueFilter.campus:
          mine = false;
        case _QueueFilter.assignedToMe:
          assignedToMe = true;
        case _QueueFilter.unclaimed:
          unclaimed = true;
        case _QueueFilter.needsTriage:
          statusParam ??= 'REPORTED,REOPENED';
        case _QueueFilter.overdue:
          overdue = true;
        case _QueueFilter.allDept:
          break;
      }

      final result = await widget.controller.api.listComplaints(
        status: statusParam,
        departmentId: _departmentFilter,
        mine: mine,
        assignedToMe: assignedToMe,
        unclaimed: unclaimed,
        overdue: overdue,
        q: _searchController.text,
        sort: _isStaffOrAbove ? 'priority' : null,
        page: nextPage,
        size: 20,
      );

      if (!mounted) return;
      setState(() {
        _complaints = reset ? result.items : <ComplaintSummary>[..._complaints, ...result.items];
        _page = result.page;
        _totalPages = result.totalPages;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
          _loadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not load complaints.';
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait<void>(<Future<void>>[
      _loadComplaints(reset: true),
      widget.controller.refreshNotifications(),
      widget.controller.refreshAnalytics(),
    ]);
  }

  Future<void> _openReportFlow() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ReportFlowPage(
          controller: widget.controller,
          photoPicker: widget.photoPicker,
          onSubmitted: (_) {
            _refreshAll();
          },
        ),
      ),
    );
  }

  Future<void> _openComplaint(String complaintId) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => IssueDetailPage(
          controller: widget.controller,
          complaintId: complaintId,
          photoPicker: widget.photoPicker,
          onChanged: () {
            _refreshAll();
          },
        ),
      ),
    );
    if (mounted) {
      await _refreshAll();
    }
  }

  Future<void> _openChangePasswordDialog() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ChangePasswordDialog(controller: widget.controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final unread = widget.controller.unreadNotificationCount;

    final destinations = _isStaffOrAbove
        ? <NavigationDestination>[
            const NavigationDestination(icon: Icon(Icons.inbox_outlined), label: 'Queue'),
            const NavigationDestination(icon: Icon(Icons.analytics_outlined), label: 'Analytics'),
            NavigationDestination(
              icon: _NotificationIcon(count: unread),
              label: 'Updates',
            ),
            const NavigationDestination(icon: Icon(Icons.account_circle_outlined), label: 'Profile'),
          ]
        : <NavigationDestination>[
            const NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
            NavigationDestination(
              icon: _NotificationIcon(count: unread),
              label: 'Updates',
            ),
            const NavigationDestination(icon: Icon(Icons.account_circle_outlined), label: 'Profile'),
          ];

    final effectiveTab = _tabIndex.clamp(0, destinations.length - 1);
    final isQueueTab = effectiveTab == 0;
    final isAnalyticsTab = _isStaffOrAbove && effectiveTab == 1;
    final isUpdatesTab = (_isStaffOrAbove && effectiveTab == 2) || (!_isStaffOrAbove && effectiveTab == 1);

    final screenTitle = isQueueTab
        ? (_isStaffOrAbove ? 'Operations queue' : 'Campus home')
        : (isAnalyticsTab ? 'Campus analytics' : (isUpdatesTab ? 'Updates' : 'Profile'));

    return FixScreen(
      title: screenTitle,
      bannerMessage: _error ?? widget.controller.bannerError,
      onBannerAction: _refreshAll,
      headerActions: <Widget>[
        if (isQueueTab)
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search complaints',
            icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
            onPressed: () {
              setState(() {
                _searching = !_searching;
                if (!_searching) _searchController.clear();
              });
              if (!_searching) _loadComplaints(reset: true);
            },
          ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: _refreshAll,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: Column(
        children: <Widget>[
          Expanded(
            child: isQueueTab
                ? _buildComplaintsTab(context)
                : (isAnalyticsTab
                    ? _buildAnalyticsTab(context)
                    : (isUpdatesTab ? _buildUpdatesTab(context) : _buildProfileTab(context))),
          ),
          if (isQueueTab && (_user.role == UserRole.student || _user.role == UserRole.admin))
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 10),
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  key: const ValueKey<String>('start-report'),
                  onPressed: _openReportFlow,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Report a problem'),
                ),
              ),
            ),
          NavigationBar(
            selectedIndex: effectiveTab,
            onDestinationSelected: (index) {
              setState(() => _tabIndex = index);
              if ((_isStaffOrAbove && index == 1) ||
                  (_isStaffOrAbove && index == 2) ||
                  (!_isStaffOrAbove && index == 1)) {
                widget.controller.refreshNotifications();
                widget.controller.refreshAnalytics();
              }
            },
            backgroundColor: colors.surfaceContainer,
            indicatorColor: colors.primaryContainer,
            destinations: destinations,
          ),
        ],
      ),
    );
  }

  Widget _buildComplaintsTab(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final analytics = widget.controller.analytics;

    ComplaintSummary? featuredResolved;
    if (_user.role == UserRole.student && _queueFilter == _QueueFilter.mine) {
      for (final c in _complaints) {
        if (c.isMine && c.status == ComplaintStatus.resolved) {
          featuredResolved = c;
          break;
        }
      }
    }

    final remaining = _complaints
        .where((c) => featuredResolved == null || c.id != featuredResolved.id)
        .toList();

    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (_searching) ...<Widget>[
              TextField(
                key: const ValueKey<String>('home-search'),
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _loadComplaints(reset: true),
                decoration: InputDecoration(
                  hintText: 'Search by code, title, or place',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: IconButton(
                    tooltip: 'Run search',
                    onPressed: () => _loadComplaints(reset: true),
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              _isStaffOrAbove ? 'Hello, ${_user.fullName}' : 'My issues',
              style: text.displaySmall,
            ),
            const SizedBox(height: 4),
            Text(
              _isStaffOrAbove
                  ? '${_user.role.label} queue · live campus operations'
                  : 'Track your reports and open campus activity',
              style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
            if (analytics != null) ...<Widget>[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _StatPill(label: 'Open', value: analytics.openCount),
                  _StatPill(label: 'In progress', value: analytics.inProgressCount),
                  _StatPill(label: 'Needs check', value: analytics.awaitingVerificationCount),
                  if (_isStaffOrAbove)
                    _StatPill(
                      label: 'Overdue',
                      value: analytics.overdueCount,
                      alert: analytics.overdueCount > 0,
                    )
                  else
                    _StatPill(label: 'Closed', value: analytics.verifiedCount),
                ],
              ),
            ],
            const SizedBox(height: 16),
            _buildQueueSegmentedControl(),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  ChoiceChip(
                    label: const Text('All statuses'),
                    selected: _statusFilter == null,
                    onSelected: (_) {
                      setState(() => _statusFilter = null);
                      _loadComplaints(reset: true);
                    },
                  ),
                  for (final status in <ComplaintStatus>[
                    ComplaintStatus.reported,
                    ComplaintStatus.assigned,
                    ComplaintStatus.inProgress,
                    ComplaintStatus.resolved,
                    ComplaintStatus.verified,
                  ]) ...<Widget>[
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: Text(status.label),
                      selected: _statusFilter == status,
                      onSelected: (_) {
                        setState(() => _statusFilter = _statusFilter == status ? null : status);
                        _loadComplaints(reset: true);
                      },
                    ),
                  ],
                ],
              ),
            ),
            if (_user.role == UserRole.admin && widget.controller.departments.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              DropdownButtonFormField<String?>(
                initialValue: _departmentFilter,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Filter by department',
                  prefixIcon: Icon(Icons.apartment_rounded),
                ),
                items: <DropdownMenuItem<String?>>[
                  const DropdownMenuItem<String?>(value: null, child: Text('All departments')),
                  for (final d in widget.controller.departments)
                    DropdownMenuItem<String?>(value: d.id, child: Text('${d.name} (${d.code})')),
                ],
                onChanged: (value) {
                  setState(() => _departmentFilter = value);
                  _loadComplaints(reset: true);
                },
              ),
            ],
            const SizedBox(height: 18),
            if (featuredResolved != null) ...<Widget>[
              _FeaturedResolvedCard(
                issue: featuredResolved,
                onOpen: () => _openComplaint(featuredResolved!.id),
              ),
              const SizedBox(height: 22),
            ],
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (remaining.isEmpty && featuredResolved == null)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: <Widget>[
                    const MoonGraphic(phase: MoonPhase.crescent, size: 72),
                    const SizedBox(height: 12),
                    Text('No complaints in this view', style: text.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Try switching filter tabs or pull down to refresh.',
                      textAlign: TextAlign.center,
                      style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              )
            else ...<Widget>[
              for (final issue in remaining)
                _ComplaintRow(
                  issue: issue,
                  onTap: () => _openComplaint(issue.id),
                ),
              if (_page + 1 < _totalPages) ...<Widget>[
                const SizedBox(height: 14),
                OutlinedButton(
                  onPressed: _loadingMore ? null : () => _loadComplaints(reset: false),
                  child: Text(_loadingMore ? 'Loading...' : 'Load more'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQueueSegmentedControl() {
    if (_user.role == UserRole.student) {
      return SegmentedButton<_QueueFilter>(
        segments: const <ButtonSegment<_QueueFilter>>[
          ButtonSegment<_QueueFilter>(
            value: _QueueFilter.mine,
            label: Text('My complaints', maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          ButtonSegment<_QueueFilter>(
            value: _QueueFilter.campus,
            label: Text('Campus activity', maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
        selected: <_QueueFilter>{_queueFilter},
        onSelectionChanged: (sel) {
          setState(() => _queueFilter = sel.first);
          _loadComplaints(reset: true);
        },
      );
    }
    if (_user.role == UserRole.staff) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          _queueFilterChip('Assigned to me', _QueueFilter.assignedToMe),
          _queueFilterChip('Department pool', _QueueFilter.unclaimed),
          _queueFilterChip('All department', _QueueFilter.allDept),
        ],
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        _queueFilterChip('Needs triage', _QueueFilter.needsTriage),
        _queueFilterChip('Unclaimed', _QueueFilter.unclaimed),
        _queueFilterChip('Overdue', _QueueFilter.overdue),
        _queueFilterChip('All queue', _QueueFilter.allDept),
      ],
    );
  }

  Widget _queueFilterChip(String label, _QueueFilter value) {
    final selected = _queueFilter == value;
    final colors = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: colors.primary,
      labelStyle: TextStyle(
        color: selected ? colors.onPrimary : colors.onSurface,
        fontWeight: FontWeight.w700,
      ),
      showCheckmark: false,
      onSelected: (_) {
        setState(() {
          _queueFilter = value;
          if (value == _QueueFilter.needsTriage) {
            _statusFilter = null;
          }
        });
        _loadComplaints(reset: true);
      },
    );
  }

  Widget _buildAnalyticsTab(BuildContext context) {
    final analytics = widget.controller.analytics;
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (analytics == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: widget.controller.refreshAnalytics,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Operations overview', style: text.headlineSmall),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                _KpiCard(label: 'Total', value: analytics.totalComplaints),
                _KpiCard(label: 'Open', value: analytics.openCount),
                _KpiCard(label: 'In progress', value: analytics.inProgressCount),
                _KpiCard(label: 'Awaiting check', value: analytics.awaitingVerificationCount),
                _KpiCard(label: 'Verified', value: analytics.verifiedCount),
                _KpiCard(label: 'Overdue SLA', value: analytics.overdueCount, highlightAlert: analytics.overdueCount > 0),
              ],
            ),
            const SizedBox(height: 24),
            Text('By status', style: text.titleMedium),
            const SizedBox(height: 10),
            for (final s in analytics.byStatus)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(child: Text(ComplaintStatus.fromApi(s.status).label)),
                      Text('${s.count}', style: text.titleMedium),
                    ],
                  ),
                ),
              ),
            if (analytics.byDepartment.isNotEmpty) ...<Widget>[
              const SizedBox(height: 20),
              Text('Open by department', style: text.titleMedium),
              const SizedBox(height: 10),
              for (final d in analytics.byDepartment)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(child: Text('${d.departmentName} (${d.departmentCode})')),
                        Text('${d.openCount}', style: text.titleMedium),
                      ],
                    ),
                  ),
                ),
            ],
            if (analytics.createdPerDay.isNotEmpty) ...<Widget>[
              const SizedBox(height: 20),
              Text('Recent daily intake', style: text.titleMedium),
              const SizedBox(height: 10),
              for (final day in analytics.createdPerDay.reversed.take(7))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: <Widget>[
                      Expanded(child: Text(day.day, style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant))),
                      Text('${day.count} reports', style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUpdatesTab(BuildContext context) {
    final list = widget.controller.notifications;
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return RefreshIndicator(
      onRefresh: widget.controller.refreshNotifications,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Notifications', style: text.headlineSmall),
            const SizedBox(height: 6),
            Text(
              list == null
                  ? 'Loading updates...'
                  : '${list.unreadCount} unread update${list.unreadCount == 1 ? '' : 's'}',
              style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            if (list == null)
              const Center(child: CircularProgressIndicator())
            else if (list.items.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Text('You have no notifications yet.'),
              )
            else
              for (final item in list.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: item.isUnread ? colors.primaryContainer.withValues(alpha: 0.45) : colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () async {
                        if (item.isUnread) {
                          await widget.controller.markNotificationRead(item.id);
                        }
                        if (item.complaintId != null && mounted) {
                          await _openComplaint(item.complaintId!);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Icon(
                              item.isUnread ? Icons.mark_email_unread_outlined : Icons.drafts_outlined,
                              color: item.isUnread ? colors.primary : colors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    item.message.isEmpty ? item.type : item.message,
                                    style: text.bodyLarge?.copyWith(
                                      fontWeight: item.isUnread ? FontWeight.w700 : FontWeight.w400,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    formatRelativeTime(item.createdAt),
                                    style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileTab(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final deptName = _user.departmentId == null
        ? null
        : widget.controller.departments
            .where((d) => d.id == _user.departmentId)
            .map((d) => d.name)
            .firstOrNull;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: colors.primaryContainer,
                      child: Icon(Icons.person_outline_rounded, color: colors.onPrimaryContainer),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(_user.fullName, style: text.titleMedium),
                          Text(_user.email, style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: <Widget>[
                    Chip(label: Text(_user.role.label)),
                    if (deptName != null) Chip(label: Text(deptName)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            tileColor: colors.surfaceContainerLow,
            leading: const Icon(Icons.lock_reset_rounded),
            title: const Text('Change password'),
            subtitle: const Text('Update your campus account passphrase'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _openChangePasswordDialog,
          ),
          const SizedBox(height: 10),
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            tileColor: colors.surfaceContainerLow,
            leading: const Icon(Icons.sync_rounded),
            title: const Text('Refresh campus data'),
            subtitle: const Text('Reload categories, locations, and counts'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _refreshAll,
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            key: const ValueKey<String>('sign-out-button'),
            onPressed: () => widget.controller.signOut(),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

class _NotificationIcon extends StatelessWidget {
  const _NotificationIcon({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: count > 0,
      label: Text(count > 99 ? '99+' : '$count'),
      child: const Icon(Icons.notifications_outlined),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, required this.value, this.alert = false});
  final String label;
  final int value;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: alert ? colors.errorContainer : colors.surfaceContainer,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        '$value $label',
        style: text.bodyMedium?.copyWith(
          color: alert ? colors.onErrorContainer : colors.onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.label, required this.value, this.highlightAlert = false});
  final String label;
  final int value;
  final bool highlightAlert;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      width: 152,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlightAlert ? colors.errorContainer : colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '$value',
            style: text.headlineSmall?.copyWith(
              color: highlightAlert ? colors.onErrorContainer : colors.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: text.bodyMedium?.copyWith(
              color: highlightAlert ? colors.onErrorContainer : colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturedResolvedCard extends StatelessWidget {
  const _FeaturedResolvedCard({required this.issue, required this.onOpen});
  final ComplaintSummary issue;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return MoonArch(
      height: 252,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            const MoonGraphic(phase: MoonPhase.almostFull, size: 74),
            const SizedBox(height: 8),
            Text(
              issue.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.titleMedium,
            ),
            const SizedBox(height: 2),
            Text('${issue.code} · Awaiting your check', textAlign: TextAlign.center),
            const SizedBox(height: 10),
            FilledButton(onPressed: onOpen, child: const Text('Check it')),
          ],
        ),
      ),
    );
  }
}

class _ComplaintRow extends StatelessWidget {
  const _ComplaintRow({required this.issue, required this.onTap});
  final ComplaintSummary issue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final phase = switch (issue.status) {
      ComplaintStatus.inProgress => MoonPhase.half,
      ComplaintStatus.resolved => MoonPhase.almostFull,
      ComplaintStatus.verified => MoonPhase.full,
      _ => MoonPhase.crescent,
    };

    return Column(
      children: <Widget>[
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: Row(
              children: <Widget>[
                MoonGraphic(phase: phase, size: 42),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Wrap(
                        spacing: 8,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          Text(
                            issue.code,
                            style: text.bodyMedium?.copyWith(
                              color: colors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (issue.departmentCode != null)
                            Text(
                              issue.departmentCode!,
                              style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          if (issue.isOverdue)
                            Text(
                              'OVERDUE',
                              style: text.bodyMedium?.copyWith(
                                color: colors.error,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        issue.title,
                        style: text.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${issue.locationName} · ${issue.status.label}',
                        style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.controller});
  final AppController controller;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _next = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.changePassword(
        currentPassword: _current.text,
        newPassword: _next.text,
      );
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change password'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            TextField(
              controller: _current,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Current password'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _next,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'New password',
                helperText: 'At least 12 characters',
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _submit, child: const Text('Update')),
      ],
    );
  }
}
