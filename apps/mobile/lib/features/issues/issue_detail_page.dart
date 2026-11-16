import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../design/widgets.dart';
import '../../preview/photo_picker.dart';
import '../../state/app_controller.dart';
import 'loop_closed_page.dart';

/// Live complaint detail view with authenticated attachment rendering, full event
/// timeline, notes, and role-appropriate workflow actions.
class IssueDetailPage extends StatefulWidget {
  const IssueDetailPage({
    required this.controller,
    required this.complaintId,
    required this.photoPicker,
    required this.onChanged,
    super.key,
  });

  final AppController controller;
  final String complaintId;
  final PreviewPhotoPicker photoPicker;
  final VoidCallback onChanged;

  @override
  State<IssueDetailPage> createState() => _IssueDetailPageState();
}

class _IssueDetailPageState extends State<IssueDetailPage> {
  final TextEditingController _noteController = TextEditingController();
  ComplaintDetail? _detail;
  bool _loading = true;
  bool _mutating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.controller.api.getComplaint(widget.complaintId);
      if (mounted) {
        setState(() {
          _detail = detail;
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not load complaint details.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _runTransition({
    required String toStatus,
    String? note,
    String? departmentId,
    String? assignedTo,
    List<String> attachmentKeys = const <String>[],
    bool openClosedPage = false,
  }) async {
    final current = _detail;
    if (current == null || _mutating) return;

    setState(() => _mutating = true);
    try {
      final updated = await widget.controller.api.transitionComplaint(
        current.id,
        toStatus: toStatus,
        version: current.version,
        note: note,
        departmentId: departmentId,
        assignedTo: assignedTo,
        attachmentKeys: attachmentKeys,
      );
      if (!mounted) return;
      widget.onChanged();
      if (openClosedPage) {
        await Navigator.of(context).pushReplacement<void, void>(
          MaterialPageRoute<void>(builder: (_) => LoopClosedPage(code: updated.code)),
        );
        return;
      }
      setState(() => _detail = updated);
      _showMessage('Updated to ${updated.status.label}.');
    } on ApiException catch (e) {
      if (!mounted) return;
      _showMessage(e.message);
      if (e.isConflict) {
        await _load();
      }
    } catch (_) {
      if (mounted) _showMessage('Could not update status.');
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _postNote() async {
    final note = _noteController.text.trim();
    final current = _detail;
    if (note.isEmpty || current == null || _mutating) return;

    setState(() => _mutating = true);
    try {
      final updated = await widget.controller.api.addNote(current.id, note);
      if (!mounted) return;
      _noteController.clear();
      setState(() => _detail = updated);
      widget.onChanged();
      _showMessage('Note added.');
    } on ApiException catch (e) {
      if (mounted) _showMessage(e.message);
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _promptReopen() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _NoteDialog(
        title: 'What still needs fixing?',
        hint: 'Describe what is still unresolved',
        confirmLabel: 'Reopen issue',
      ),
    );
    if (reason != null && mounted) {
      await _runTransition(toStatus: 'REOPENED', note: reason);
    }
  }

  Future<void> _promptRelease() async {
    final note = await showDialog<String>(
      context: context,
      builder: (_) => const _NoteDialog(
        title: 'Release back to queue',
        hint: 'Explain why this issue is being released',
        confirmLabel: 'Release',
      ),
    );
    if (note != null && mounted) {
      await _runTransition(toStatus: 'ASSIGNED', note: note);
    }
  }

  Future<void> _promptReject() async {
    final note = await showDialog<String>(
      context: context,
      builder: (_) => const _NoteDialog(
        title: 'Reject complaint',
        hint: 'Provide a clear reason for rejecting',
        confirmLabel: 'Reject',
      ),
    );
    if (note != null && mounted) {
      await _runTransition(toStatus: 'REJECTED', note: note);
    }
  }

  Future<void> _promptResolve() async {
    final detail = _detail;
    if (detail == null) return;
    final result = await showDialog<_ResolveDialogResult>(
      context: context,
      builder: (_) => _ResolveDialog(
        allowPhotos: detail.photoPolicy != 'DISABLED',
        controller: widget.controller,
        photoPicker: widget.photoPicker,
      ),
    );
    if (result != null && mounted) {
      await _runTransition(
        toStatus: 'RESOLVED',
        note: result.note,
        attachmentKeys: result.attachmentKeys,
      );
    }
  }

  Future<void> _promptRouteOrReassign({required bool isRoute}) async {
    final detail = _detail;
    if (detail == null) return;
    final result = await showDialog<_RouteDialogResult>(
      context: context,
      builder: (_) => _RouteOrReassignDialog(
        controller: widget.controller,
        complaint: detail,
        isInitialRoute: isRoute,
      ),
    );
    if (result != null && mounted) {
      await _runTransition(
        toStatus: 'ASSIGNED',
        departmentId: result.departmentId,
        assignedTo: result.assignedTo,
        note: result.note,
      );
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return FixScreen(
      title: _detail?.code ?? 'Issue detail',
      onBack: () => Navigator.of(context).pop(),
      bannerMessage: _error,
      onBannerAction: _load,
      headerActions: <Widget>[
        IconButton(
          tooltip: 'Refresh issue',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_detail == null ? const SizedBox.shrink() : _buildBody(context, _detail!)),
    );
  }

  Widget _buildBody(BuildContext context, ComplaintDetail issue) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final user = widget.controller.currentUser;
    final role = user?.role ?? UserRole.student;

    final phase = switch (issue.status) {
      ComplaintStatus.verified => MoonPhase.full,
      ComplaintStatus.resolved => MoonPhase.almostFull,
      ComplaintStatus.inProgress => MoonPhase.half,
      _ => MoonPhase.crescent,
    };

    final canPostNote = user != null &&
        (role.isStaffOrAbove || issue.isMine);

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainer,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text('# ${issue.code}', style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: StatusBadge(status: issue.status),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            MoonArch(
              height: 215,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  MoonGraphic(phase: phase, size: 128, orbit: true),
                  const SizedBox(height: 8),
                  Text(
                    issue.status == ComplaintStatus.resolved && issue.isMine
                        ? 'Awaiting your confirmation'
                        : issue.status.label,
                    textAlign: TextAlign.center,
                    style: text.bodyLarge?.copyWith(
                      color: colors.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(issue.title, style: text.headlineSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: <Widget>[
                Chip(label: Text('${issue.severity.label} severity')),
                if (issue.departmentName != null) Chip(label: Text(issue.departmentName!)),
                if (issue.isSensitive)
                  Chip(
                    backgroundColor: colors.errorContainer,
                    label: Text('Restricted', style: TextStyle(color: colors.onErrorContainer)),
                  ),
                if (issue.isOverdue)
                  Chip(
                    backgroundColor: colors.errorContainer,
                    label: Text('SLA overdue', style: TextStyle(color: colors.onErrorContainer)),
                  ),
              ],
            ),
            if (issue.description != null && issue.description!.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(issue.description!, style: text.bodyLarge),
              ),
            ],
            const SizedBox(height: 16),
            _DetailLine(label: 'Category', value: issue.categoryName),
            _DetailLine(label: 'Location', value: issue.locationName),
            if (issue.assigneeName != null) _DetailLine(label: 'Assigned to', value: issue.assigneeName!),
            if (issue.reporter != null)
              _DetailLine(
                label: 'Reporter',
                value: '${issue.reporter!.fullName} (${issue.reporter!.email})',
              ),
            if (issue.slaDueAt != null)
              _DetailLine(
                label: 'SLA due',
                value: '${formatRelativeTime(issue.slaDueAt!)} (${issue.isOverdue ? 'Overdue' : 'On track'})',
              ),
            if (issue.reopenCount > 0)
              _DetailLine(label: 'Reopened', value: '${issue.reopenCount} time${issue.reopenCount == 1 ? '' : 's'}'),
            const SizedBox(height: 18),
            if (_buildWorkflowActions(issue, user).isNotEmpty) ...<Widget>[
              Text('Actions', style: text.titleMedium),
              const SizedBox(height: 10),
              ..._buildWorkflowActions(issue, user),
              const SizedBox(height: 18),
            ],
            if (issue.attachments.isNotEmpty) ...<Widget>[
              Text('Photos (${issue.attachments.length})', style: text.titleMedium),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  for (final att in issue.attachments)
                    _AuthenticatedAttachmentCard(
                      controller: widget.controller,
                      attachment: att,
                    ),
                ],
              ),
              const SizedBox(height: 18),
            ],
            Text('Timeline', style: text.titleMedium),
            const SizedBox(height: 8),
            if (issue.events.isEmpty)
              Text('No events recorded yet.', style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant))
            else
              for (final event in issue.events) _EventTile(event: event),
            if (canPostNote) ...<Widget>[
              const SizedBox(height: 18),
              Text('Add a note', style: text.titleMedium),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      key: const ValueKey<String>('add-note-input'),
                      controller: _noteController,
                      enabled: !_mutating,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(hintText: 'Share an update or question'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey<String>('add-note-submit'),
                    onPressed: _mutating ? null : _postNote,
                    child: const Text('Send'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildWorkflowActions(ComplaintDetail issue, UserAccount? user) {
    if (user == null) return const <Widget>[];
    final role = user.role;
    final widgets = <Widget>[];

    if (role == UserRole.student && issue.isMine && issue.status == ComplaintStatus.resolved) {
      widgets.add(
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey<String>('action-reopen'),
                onPressed: _mutating ? null : _promptReopen,
                icon: const Icon(Icons.close_rounded),
                label: const Text('Not fixed'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey<String>('action-verify'),
                onPressed: _mutating
                    ? null
                    : () => _runTransition(toStatus: 'VERIFIED', openClosedPage: true),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Fixed'),
              ),
            ),
          ],
        ),
      );
      return widgets;
    }

    if ((role == UserRole.staff || role == UserRole.supervisor) &&
        issue.status == ComplaintStatus.assigned &&
        (issue.assignedTo == null || issue.assignedTo == user.id)) {
      widgets.add(
        PrimaryAction(
          key: const ValueKey<String>('action-claim'),
          label: 'Start work',
          icon: Icons.play_arrow_rounded,
          busy: _mutating,
          onPressed: () => _runTransition(toStatus: 'IN_PROGRESS'),
        ),
      );
    }

    if ((role == UserRole.staff || role == UserRole.supervisor) &&
        issue.status == ComplaintStatus.inProgress &&
        (role == UserRole.supervisor || issue.assignedTo == user.id)) {
      if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 10));
      widgets.add(
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey<String>('action-release'),
                onPressed: _mutating ? null : _promptRelease,
                icon: const Icon(Icons.undo_rounded),
                label: const Text('Release'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey<String>('action-resolve'),
                onPressed: _mutating ? null : _promptResolve,
                icon: const Icon(Icons.task_alt_rounded),
                label: const Text('Resolve'),
              ),
            ),
          ],
        ),
      );
    }

    if ((role == UserRole.supervisor || role == UserRole.admin) &&
        issue.status == ComplaintStatus.reported) {
      widgets.add(
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey<String>('action-reject'),
                onPressed: _mutating ? null : _promptReject,
                icon: const Icon(Icons.block_rounded),
                label: const Text('Reject'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey<String>('action-route'),
                onPressed: _mutating ? null : () => _promptRouteOrReassign(isRoute: true),
                icon: const Icon(Icons.alt_route_rounded),
                label: const Text('Route'),
              ),
            ),
          ],
        ),
      );
    }

    if ((role == UserRole.supervisor || role == UserRole.admin) &&
        issue.status == ComplaintStatus.assigned) {
      if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 10));
      widgets.add(
        OutlinedButton.icon(
          key: const ValueKey<String>('action-reassign'),
          onPressed: _mutating ? null : () => _promptRouteOrReassign(isRoute: false),
          icon: const Icon(Icons.swap_horiz_rounded),
          label: const Text('Reassign team / staff'),
        ),
      );
    }

    return widgets;
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 104,
            child: Text(label, style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});
  final ComplaintEvent event;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final who = event.actorName != null ? '${event.actorName} (${event.actorRole})' : event.actorRole;
    final transition = event.fromStatus != null && event.toStatus != null && event.fromStatus != event.toStatus
        ? ' · ${event.fromStatus} -> ${event.toStatus}'
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${event.eventType}$transition',
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                formatRelativeTime(event.createdAt),
                style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(who, style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
          if (event.note != null && event.note!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(event.note!, style: text.bodyLarge),
          ],
        ],
      ),
    );
  }
}

class _AuthenticatedAttachmentCard extends StatefulWidget {
  const _AuthenticatedAttachmentCard({
    required this.controller,
    required this.attachment,
  });

  final AppController controller;
  final AttachmentMetadata attachment;

  @override
  State<_AuthenticatedAttachmentCard> createState() => _AuthenticatedAttachmentCardState();
}

class _AuthenticatedAttachmentCardState extends State<_AuthenticatedAttachmentCard> {
  late Future<Uint8List> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.controller.api.fetchAttachmentBytes(widget.attachment.id);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (snapshot.hasError) {
          final err = snapshot.error;
          final missing = err is ApiException && err.isMissingFile;
          return Container(
            width: 148,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.image_not_supported_outlined, color: colors.onSurfaceVariant),
                const SizedBox(height: 6),
                Text(
                  missing ? 'Sample photo unavailable on server' : 'Photo unavailable',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          );
        }
        final bytes = snapshot.data!;
        return GestureDetector(
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => Dialog(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Image.memory(bytes, fit: BoxFit.contain),
                    const SizedBox(height: 8),
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
                  ],
                ),
              ),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              children: <Widget>[
                Image.memory(
                  bytes,
                  width: 112,
                  height: 112,
                  fit: BoxFit.cover,
                ),
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      widget.attachment.kind,
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({
    required this.title,
    required this.hint,
    required this.confirmLabel,
  });

  final String title;
  final String hint;
  final String confirmLabel;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey<String>('dialog-note'),
        controller: _controller,
        minLines: 2,
        maxLines: 4,
        maxLength: 500,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(hintText: widget.hint),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _controller.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, _controller.text.trim()),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _ResolveDialogResult {
  const _ResolveDialogResult({required this.note, required this.attachmentKeys});
  final String note;
  final List<String> attachmentKeys;
}

class _ResolveDialog extends StatefulWidget {
  const _ResolveDialog({
    required this.allowPhotos,
    required this.controller,
    required this.photoPicker,
  });

  final bool allowPhotos;
  final AppController controller;
  final PreviewPhotoPicker photoPicker;

  @override
  State<_ResolveDialog> createState() => _ResolveDialogState();
}

class _ResolveDialogState extends State<_ResolveDialog> {
  final TextEditingController _note = TextEditingController();
  final List<String> _uploadedKeys = <String>[];
  bool _uploading = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _attachPhoto() async {
    if (_uploading) return;
    setState(() => _uploading = true);
    try {
      final picked = await widget.photoPicker.pickPhoto();
      if (!mounted || picked == null) return;
      final uploaded = await widget.controller.api.uploadAttachment(
        bytes: picked.bytes,
        filename: 'resolution.png',
        mimeType: 'image/png',
      );
      if (mounted) setState(() => _uploadedKeys.add(uploaded.storageKey));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Mark resolved'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              key: const ValueKey<String>('resolve-note'),
              controller: _note,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(hintText: 'Describe what was repaired'),
            ),
            if (widget.allowPhotos) ...<Widget>[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _uploading ? null : _attachPhoto,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: Text(_uploading
                    ? 'Uploading...'
                    : (_uploadedKeys.isEmpty
                        ? 'Add resolution photo (optional)'
                        : '${_uploadedKeys.length} photo attached')),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _note.text.trim().isEmpty || _uploading
              ? null
              : () => Navigator.pop(
                    context,
                    _ResolveDialogResult(note: _note.text.trim(), attachmentKeys: _uploadedKeys),
                  ),
          child: const Text('Mark resolved'),
        ),
      ],
    );
  }
}

class _RouteDialogResult {
  const _RouteDialogResult({required this.departmentId, this.assignedTo, this.note});
  final String departmentId;
  final String? assignedTo;
  final String? note;
}

class _RouteOrReassignDialog extends StatefulWidget {
  const _RouteOrReassignDialog({
    required this.controller,
    required this.complaint,
    required this.isInitialRoute,
  });

  final AppController controller;
  final ComplaintDetail complaint;
  final bool isInitialRoute;

  @override
  State<_RouteOrReassignDialog> createState() => _RouteOrReassignDialogState();
}

class _RouteOrReassignDialogState extends State<_RouteOrReassignDialog> {
  final TextEditingController _note = TextEditingController();
  String? _departmentId;
  String? _staffId;
  List<StaffMemberModel> _staff = const <StaffMemberModel>[];
  bool _loadingStaff = false;

  @override
  void initState() {
    super.initState();
    _departmentId = widget.complaint.departmentId ??
        (widget.controller.departments.isNotEmpty ? widget.controller.departments.first.id : null);
    if (_departmentId != null) {
      _loadStaff(_departmentId!);
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadStaff(String departmentId) async {
    setState(() => _loadingStaff = true);
    try {
      final list = await widget.controller.api.listStaff(departmentId: departmentId);
      if (mounted) {
        setState(() {
          _staff = list;
          _staffId = null;
          _loadingStaff = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingStaff = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final departments = widget.controller.departments
        .where((d) => !widget.complaint.isSensitive || d.isRestricted)
        .toList();
    final requireNote = !widget.isInitialRoute;
    final canSubmit =
        _departmentId != null && (!requireNote || _note.text.trim().isNotEmpty);

    return AlertDialog(
      title: Text(widget.isInitialRoute ? 'Route complaint' : 'Reassign complaint'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            DropdownButtonFormField<String>(
              initialValue: _departmentId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Department'),
              items: departments
                  .map((d) => DropdownMenuItem<String>(value: d.id, child: Text('${d.name} (${d.code})')))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _departmentId = value);
                  _loadStaff(value);
                }
              },
            ),
            const SizedBox(height: 12),
            if (_loadingStaff)
              const LinearProgressIndicator()
            else
              DropdownButtonFormField<String?>(
                initialValue: _staffId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Assign to (optional)'),
                items: <DropdownMenuItem<String?>>[
                  const DropdownMenuItem<String?>(value: null, child: Text('Unassigned (department pool)')),
                  for (final s in _staff)
                    DropdownMenuItem<String?>(value: s.id, child: Text('${s.fullName} (${s.role.label})')),
                ],
                onChanged: (value) => setState(() => _staffId = value),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              minLines: 2,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: requireNote ? 'Reason (required)' : 'Note (optional)',
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: canSubmit
              ? () => Navigator.pop(
                    context,
                    _RouteDialogResult(
                      departmentId: _departmentId!,
                      assignedTo: _staffId,
                      note: _note.text.trim(),
                    ),
                  )
              : null,
          child: Text(widget.isInitialRoute ? 'Route' : 'Reassign'),
        ),
      ],
    );
  }
}
