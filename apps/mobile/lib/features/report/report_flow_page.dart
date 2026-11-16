import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/fix_loop_api.dart';
import '../../data/models.dart';
import '../../design/widgets.dart';
import '../../preview/photo_picker.dart';
import '../../state/app_controller.dart';

class _UploadedPhoto {
  const _UploadedPhoto({required this.bytes, required this.uploaded});
  final Uint8List bytes;
  final UploadedAttachment uploaded;
}

/// Four-step guided complaint submission backed by live categories, dynamic-depth
/// locations, similarity lookup, real photo uploads, and idempotent submission.
class ReportFlowPage extends StatefulWidget {
  const ReportFlowPage({
    required this.controller,
    required this.photoPicker,
    required this.onSubmitted,
    super.key,
  });

  final AppController controller;
  final PreviewPhotoPicker photoPicker;
  final ValueChanged<ComplaintDetail> onSubmitted;

  @override
  State<ReportFlowPage> createState() => _ReportFlowPageState();
}

class _ReportFlowPageState extends State<ReportFlowPage> {
  final TextEditingController _categorySearch = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  late final String _idempotencyKey;

  int _step = 0;
  bool _showAllCategories = false;

  CategoryModel? _category;
  final List<LocationModel> _selectedLocationLevels = <LocationModel>[];
  ComplaintSeverity _severity = ComplaintSeverity.medium;
  final List<_UploadedPhoto> _photos = <_UploadedPhoto>[];

  SimilarComplaints? _similar;
  bool _loadingSimilar = false;
  bool _uploadingPhoto = false;
  bool _submitting = false;
  ComplaintDetail? _created;

  @override
  void initState() {
    super.initState();
    _idempotencyKey = 'fl-${DateTime.now().microsecondsSinceEpoch}';
  }

  @override
  void dispose() {
    _categorySearch.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  FixLoopApi get _api => widget.controller.api;
  List<LocationModel> get _allLocations => widget.controller.locations;

  List<LocationModel> _childrenOf(String? parentId) =>
      _allLocations.where((loc) => loc.parentId == parentId).toList();

  List<LocationModel> _levelChoices(int level) {
    if (level == 0) {
      final roots = _allLocations.where((loc) => loc.parentId == null).toList();
      if (roots.length == 1) {
        final underRoot = _childrenOf(roots.first.id);
        if (underRoot.isNotEmpty) return underRoot;
      }
      return roots;
    }
    if (level - 1 >= _selectedLocationLevels.length) return const <LocationModel>[];
    return _childrenOf(_selectedLocationLevels[level - 1].id);
  }

  LocationModel? get _selectedLeafLocation {
    if (_selectedLocationLevels.isEmpty) return null;
    final last = _selectedLocationLevels.last;
    if (_childrenOf(last.id).isNotEmpty) return null;
    return last;
  }

  String get _locationDisplay {
    if (_selectedLocationLevels.isEmpty) return '';
    return _selectedLocationLevels.map((l) => l.name).join(' · ');
  }

  bool get _hasValidDetails {
    final titleLen = _titleController.text.trim().length;
    if (titleLen < 5 || titleLen > 120) return false;
    if (_category?.photoPolicy == 'REQUIRED' && _photos.isEmpty) return false;
    return true;
  }

  void _back() {
    if (_step == 0 || _step == 4) {
      Navigator.of(context).pop();
    } else {
      setState(() => _step--);
    }
  }

  void _next() {
    if (_step == 1 && _selectedLeafLocation != null) {
      setState(() => _step = 2);
    } else if (_step == 2 && _hasValidDetails) {
      setState(() => _step = 3);
    }
  }

  Future<void> _selectCategory(CategoryModel cat) async {
    setState(() {
      _category = cat;
      _severity = cat.defaultSeverity;
      if (cat.photoPolicy == 'DISABLED') {
        _photos.clear();
      }
      _similar = null;
      _step = 1;
    });
    final leaf = _selectedLeafLocation;
    if (leaf != null && !cat.isSensitive) {
      await _loadSimilar(leaf.id, cat.id);
    }
  }

  Future<void> _selectLocationAtLevel(int level, String? locationId) async {
    if (locationId == null) return;
    final chosen = _allLocations.firstWhere((l) => l.id == locationId);
    setState(() {
      _selectedLocationLevels.removeRange(level, _selectedLocationLevels.length);
      _selectedLocationLevels.add(chosen);
      _similar = null;
    });

    final leaf = _selectedLeafLocation;
    final cat = _category;
    if (leaf != null && cat != null && !cat.isSensitive) {
      await _loadSimilar(leaf.id, cat.id);
    }
  }

  Future<void> _loadSimilar(String locationId, String categoryId) async {
    setState(() => _loadingSimilar = true);
    try {
      final result = await _api.findSimilar(locationId: locationId, categoryId: categoryId);
      if (mounted) setState(() => _similar = result);
    } catch (_) {
      // Non-blocking hint; ignore errors silently.
    } finally {
      if (mounted) setState(() => _loadingSimilar = false);
    }
  }

  Future<void> _pickAndUploadPhoto() async {
    if (_uploadingPhoto || _photos.length >= 5) return;
    setState(() => _uploadingPhoto = true);
    try {
      final picked = await widget.photoPicker.pickPhoto();
      if (!mounted || picked == null) return;
      final mime = _detectMime(picked.bytes);
      final ext = mime == 'image/png' ? 'png' : (mime == 'image/webp' ? 'webp' : 'jpg');
      final uploaded = await _api.uploadAttachment(
        bytes: picked.bytes,
        filename: 'issue-photo.$ext',
        mimeType: mime,
      );
      if (!mounted) return;
      setState(() => _photos.add(_UploadedPhoto(bytes: picked.bytes, uploaded: uploaded)));
    } on PhotoTooLargeException {
      if (mounted) _showMessage('Choose a photo smaller than 5 MB.');
    } on ApiException catch (e) {
      if (mounted) _showMessage(e.message);
    } catch (_) {
      if (mounted) _showMessage('Could not upload photo right now.');
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _submitComplaint() async {
    final cat = _category;
    final loc = _selectedLeafLocation;
    if (cat == null || loc == null || !_hasValidDetails || _submitting) return;

    setState(() => _submitting = true);
    try {
      final created = await _api.createComplaint(
        categoryId: cat.id,
        locationId: loc.id,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        severity: _severity,
        attachmentKeys: _photos.map((p) => p.uploaded.storageKey).toList(),
        idempotencyKey: _idempotencyKey,
      );
      if (!mounted) return;
      widget.onSubmitted(created);
      setState(() {
        _created = created;
        _step = 4;
      });
    } on ApiException catch (e) {
      if (mounted) _showMessage(e.message);
    } catch (_) {
      if (mounted) _showMessage('Could not submit report. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  static String _detectMime(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }

  @override
  Widget build(BuildContext context) {
    final isSuccess = _step == 4;
    return PopScope<Object?>(
      canPop: _step == 0 || isSuccess,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: FixScreen(
        title: 'Report issue',
        onBack: _back,
        child: isSuccess && _created != null
            ? _ReportSuccessView(complaint: _created!, onDone: _back)
            : Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                    child: StepProgress(step: _step + 1),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      key: ValueKey<int>(_step),
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                      child: switch (_step) {
                        0 => _categoryStep(),
                        1 => _locationStep(),
                        2 => _detailsStep(),
                        _ => _reviewStep(),
                      },
                    ),
                  ),
                  if (_step > 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                      child: _bottomAction(),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _categoryStep() {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final all = widget.controller.categories;
    final query = _categorySearch.text.trim().toLowerCase();
    final filtered = all.where((cat) {
      if (query.isNotEmpty) {
        return cat.name.toLowerCase().contains(query) || cat.theme.toLowerCase().contains(query);
      }
      return _showAllCategories || all.indexOf(cat) < 6;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('What is wrong?', style: text.displaySmall),
        const SizedBox(height: 8),
        Text(
          'Select an issue category to start your campus repair loop.',
          style: text.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        TextField(
          key: const ValueKey<String>('category-search'),
          controller: _categorySearch,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Search categories',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () => setState(_categorySearch.clear),
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        ),
        const SizedBox(height: 18),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              all.isEmpty ? 'Categories are loading or unavailable.' : 'No matching categories found.',
              style: text.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 310 ? 1 : 2;
              final itemWidth = (constraints.maxWidth - (columns - 1) * 8) / columns;
              final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
              final itemHeight = 84.0 * textScale.clamp(1.0, 2.5);
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final category in filtered)
                    SizedBox(
                      width: itemWidth,
                      height: itemHeight,
                      child: _CategoryTile(
                        category: category,
                        onTap: () => _selectCategory(category),
                      ),
                    ),
                ],
              );
            },
          ),
        if (query.isEmpty && all.length > 6) ...<Widget>[
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: () => setState(() => _showAllCategories = !_showAllCategories),
            icon: Icon(_showAllCategories ? Icons.expand_less_rounded : Icons.expand_more_rounded),
            label: Text(_showAllCategories ? 'Fewer categories' : 'More categories'),
          ),
        ],
      ],
    );
  }

  Widget _locationStep() {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    // Build dynamic depth dropdowns until selected leaf has no children.
    final dropdowns = <Widget>[];
    final maxPossibleLevels = _selectedLocationLevels.length + 1;
    for (var level = 0; level < maxPossibleLevels; level++) {
      final choices = _levelChoices(level);
      if (choices.isEmpty) break;

      final selected = level < _selectedLocationLevels.length ? _selectedLocationLevels[level] : null;
      final label = _labelForChoices(choices, level);
      final icon = _iconForChoices(choices);

      dropdowns.add(
        Padding(
          padding: EdgeInsets.only(bottom: level + 1 < maxPossibleLevels ? 16 : 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 7),
                child: Text(label, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
              DropdownButtonFormField<String>(
                key: ValueKey<String>(
                  'loc-level-$level-${level == 0 ? 'root' : _selectedLocationLevels[level - 1].id}',
                ),
                initialValue: selected?.id,
                isExpanded: true,
                decoration: InputDecoration(prefixIcon: Icon(icon)),
                hint: Text('Select ${label.toLowerCase()}'),
                items: choices
                    .map(
                      (loc) => DropdownMenuItem<String>(
                        key: ValueKey<String>('loc-opt-${loc.id}'),
                        value: loc.id,
                        child: Text(loc.name, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (value) => _selectLocationAtLevel(level, value),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Where is it?', style: text.displaySmall),
        const SizedBox(height: 8),
        Text(
          'Select the exact spot on campus.',
          style: text.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        if (dropdowns.isEmpty)
          const Text('Locations are unavailable right now.')
        else
          ...dropdowns,
        if (_loadingSimilar) ...<Widget>[
          const SizedBox(height: 18),
          const LinearProgressIndicator(),
        ],
        if (_similar != null && _similar!.count > 0) ...<Widget>[
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.info_outline_rounded, color: colors.onPrimaryContainer, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${_similar!.count} open similar issue${_similar!.count == 1 ? '' : 's'} '
                    'already reported here (${_similar!.mostCommonStatus ?? 'OPEN'}). '
                    'You can still submit if yours is separate.',
                    style: text.bodyMedium?.copyWith(
                      color: colors.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _detailsStep() {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final policy = _category?.photoPolicy ?? 'OPTIONAL';
    final isPhotoDisabled = policy == 'DISABLED';
    final isPhotoRequired = policy == 'REQUIRED';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Tell us more', style: text.displaySmall),
        const SizedBox(height: 20),
        Text('Severity', style: text.titleMedium),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            for (final severity in ComplaintSeverity.values)
              ChoiceChip(
                label: Text(severity.label),
                selected: _severity == severity,
                showCheckmark: false,
                selectedColor: colors.primary,
                backgroundColor: colors.surfaceContainerHigh,
                side: BorderSide.none,
                labelStyle: TextStyle(
                  color: _severity == severity ? colors.onPrimary : colors.onSurface,
                  fontWeight: FontWeight.w700,
                ),
                onSelected: (_) => setState(() => _severity = severity),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(_severity.description, style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
        const SizedBox(height: 20),
        TextField(
          key: const ValueKey<String>('issue-title'),
          controller: _titleController,
          maxLength: 120,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Short summary',
            hintText: 'e.g. Ceiling leak above study desk',
            helperText: 'At least 5 characters',
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey<String>('issue-description'),
          controller: _descriptionController,
          minLines: 3,
          maxLines: 6,
          maxLength: 2000,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Details (optional)',
            hintText: 'Share room landmarks, timing, or extra context',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          isPhotoDisabled
              ? 'Photos disabled'
              : (isPhotoRequired ? 'Photos (required · at least 1)' : 'Photos (optional)'),
          style: text.titleMedium,
        ),
        const SizedBox(height: 6),
        if (isPhotoDisabled)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.lock_outline_rounded, size: 18, color: colors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Photographs are disabled for confidential/sensitive categories.',
                    style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          )
        else ...<Widget>[
          Text(
            'Up to 5 images, 5 MB each. Uploaded securely for maintenance staff.',
            style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              for (var index = 0; index < _photos.length; index++)
                _PhotoThumbnail(
                  bytes: _photos[index].bytes,
                  index: index,
                  onRemove: () => setState(() => _photos.removeAt(index)),
                ),
              if (_photos.length < 5)
                Tooltip(
                  message: 'Add photo',
                  child: Material(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      key: const ValueKey<String>('add-photo'),
                      borderRadius: BorderRadius.circular(14),
                      onTap: _uploadingPhoto ? null : _pickAndUploadPhoto,
                      child: SizedBox(
                        width: 96,
                        height: 96,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            if (_uploadingPhoto)
                              const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            else
                              Icon(Icons.add_a_photo_outlined, color: colors.primary),
                            const SizedBox(height: 6),
                            Text(
                              _uploadingPhoto ? 'Uploading' : 'Add photo',
                              style: text.bodyMedium?.copyWith(color: colors.primary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _reviewStep() {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Check and send', style: text.displaySmall),
        const SizedBox(height: 20),
        _ReviewRow(
          label: 'Category',
          value: _category!.name,
          onEdit: () => setState(() => _step = 0),
        ),
        _ReviewRow(
          label: 'Place',
          value: _locationDisplay,
          onEdit: () => setState(() => _step = 1),
        ),
        _ReviewRow(
          label: 'Severity',
          value: '${_severity.label} · ${_severity.description}',
          onEdit: () => setState(() => _step = 2),
        ),
        _ReviewRow(
          label: 'Summary',
          value: _titleController.text.trim(),
          onEdit: () => setState(() => _step = 2),
        ),
        if (_descriptionController.text.trim().isNotEmpty)
          _ReviewRow(
            label: 'Details',
            value: _descriptionController.text.trim(),
            onEdit: () => setState(() => _step = 2),
          ),
        _ReviewRow(
          label: 'Photos',
          value: _category!.photoPolicy == 'DISABLED' ? 'Disabled' : '${_photos.length} uploaded',
          onEdit: () => setState(() => _step = 2),
        ),
        if (_photos.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final photo in _photos)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    photo.bytes,
                    width: 58,
                    height: 58,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const SizedBox(width: 58, height: 58, child: Icon(Icons.broken_image_outlined)),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.lock_outline_rounded, color: colors.primary, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _category!.isSensitive
                    ? 'Sensitive report: routed exclusively to the restricted committee. '
                        'Hidden from campus peers and unrelated departments.'
                    : 'Your identity stays hidden from peers and service technicians.',
                style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _bottomAction() => switch (_step) {
        1 => PrimaryAction(
            label: 'Next',
            icon: Icons.arrow_forward_rounded,
            onPressed: _selectedLeafLocation != null ? _next : null,
          ),
        2 => PrimaryAction(
            label: 'Next',
            icon: Icons.arrow_forward_rounded,
            onPressed: _hasValidDetails ? _next : null,
          ),
        _ => PrimaryAction(
            key: const ValueKey<String>('submit-complaint'),
            label: 'Submit report',
            icon: Icons.send_rounded,
            busy: _submitting,
            onPressed: _submitComplaint,
          ),
      };

  static String _labelForChoices(List<LocationModel> choices, int level) {
    final firstType = choices.first.type.toUpperCase();
    return switch (firstType) {
      'CAMPUS' => 'Campus',
      'BLOCK' => 'Campus block or building',
      'FLOOR' => 'Floor level',
      'ROOM' => 'Room or space',
      'AREA' => 'Campus area',
      _ => level == 0 ? 'Area or building' : 'Specific spot',
    };
  }

  static IconData _iconForChoices(List<LocationModel> choices) {
    final firstType = choices.first.type.toUpperCase();
    return switch (firstType) {
      'BLOCK' => Icons.apartment_rounded,
      'FLOOR' => Icons.layers_outlined,
      'ROOM' => Icons.meeting_room_outlined,
      _ => Icons.place_outlined,
    };
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.onTap});
  final CategoryModel category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final badgeText = category.isSensitive
        ? 'Restricted · Private'
        : (category.photoPolicy == 'REQUIRED' ? 'Photo required' : category.defaultSeverity.label);
    return Material(
      color: colors.surfaceContainer,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 18,
                backgroundColor: colors.surfaceContainerLowest,
                child: Icon(category.icon, color: colors.primary, size: 21),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      category.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      badgeText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(
                        color: category.isSensitive ? colors.error : colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoThumbnail extends StatelessWidget {
  const _PhotoThumbnail({required this.bytes, required this.onRemove, required this.index});
  final Uint8List bytes;
  final VoidCallback onRemove;
  final int index;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.memory(
              bytes,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const ColoredBox(
                color: Colors.black12,
                child: Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: IconButton.filledTonal(
              tooltip: 'Remove photo ${index + 1}',
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.label, required this.value, required this.onEdit});
  final String label;
  final String value;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: <Widget>[
        InkWell(
          onTap: onEdit,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 78,
                  child: Text(label, style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    value,
                    textAlign: TextAlign.right,
                    style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.edit_outlined, size: 18, color: colors.primary),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

class _ReportSuccessView extends StatelessWidget {
  const _ReportSuccessView({required this.complaint, required this.onDone});
  final ComplaintDetail complaint;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          MoonArch(
            height: 236,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const MoonGraphic(phase: MoonPhase.crescent, size: 144, orbit: true),
                StatusBadge(status: complaint.status),
              ],
            ),
          ),
          const SizedBox(height: 26),
          Text('Report received', style: text.displaySmall, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: colors.surfaceContainer,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text('# ${complaint.code}', style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            complaint.departmentName != null
                ? 'Automatically routed to ${complaint.departmentName}. You can follow updates right from your home screen.'
                : 'Queued for supervisor triage. You will be notified as soon as a team picks it up.',
            style: text.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 36),
          PrimaryAction(label: 'Done', onPressed: onDone),
        ],
      ),
    );
  }
}
