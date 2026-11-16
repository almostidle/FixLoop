import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/models.dart';
import 'fix_loop_theme.dart';

/// Keeps the phone layout readable on larger web and tablet windows too.
class FixScreen extends StatelessWidget {
  const FixScreen({
    required this.title,
    required this.child,
    this.onBack,
    this.headerActions = const <Widget>[],
    this.bannerMessage,
    this.onBannerAction,
    this.bannerActionLabel = 'Retry',
    super.key,
  });

  final String title;
  final Widget child;
  final VoidCallback? onBack;
  final List<Widget> headerActions;
  final String? bannerMessage;
  final VoidCallback? onBannerAction;
  final String bannerActionLabel;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Row(
                    children: <Widget>[
                      if (onBack != null)
                        IconButton(
                          tooltip: 'Back',
                          onPressed: onBack,
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                      if (onBack != null) const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          title,
                          style: text.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      ...headerActions,
                    ],
                  ),
                ),
                if (bannerMessage != null && bannerMessage!.isNotEmpty)
                  StatusBanner(
                    message: bannerMessage!,
                    onAction: onBannerAction,
                    actionLabel: bannerActionLabel,
                  ),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StatusBanner extends StatelessWidget {
  const StatusBanner({
    required this.message,
    this.onAction,
    this.actionLabel = 'Retry',
    super.key,
  });

  final String message;
  final VoidCallback? onAction;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(24, 2, 24, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.cloud_off_rounded, size: 18, color: colors.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onErrorContainer,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          if (onAction != null)
            TextButton(
              onPressed: onAction,
              child: Text(actionLabel),
            ),
        ],
      ),
    );
  }
}

class StepProgress extends StatelessWidget {
  const StepProgress({required this.step, super.key});
  final int step;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Step $step of 4',
      child: ExcludeSemantics(
        child: Row(
          children: <Widget>[
            for (var i = 1; i <= 4; i++) ...<Widget>[
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: i == step ? 25 : 9,
                height: 9,
                decoration: BoxDecoration(
                  color: i <= step ? colors.primary : colors.outlineVariant,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              if (i != 4) const SizedBox(width: 5),
            ],
            const SizedBox(width: 8),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainer,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    'Step $step of 4',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.onSurfaceVariant,
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
}

class PrimaryAction extends StatelessWidget {
  const PrimaryAction({
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final iconData = icon;
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (busy) ...<Widget>[
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
            ],
            Flexible(child: Text(label, textAlign: TextAlign.center)),
            if (!busy && iconData != null) ...<Widget>[
              const SizedBox(width: 8),
              Icon(iconData, size: 20),
            ],
          ],
        ),
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({required this.status, super.key});
  final ComplaintStatus status;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (fill, foreground) = switch (status) {
      ComplaintStatus.reported => dark
          ? (const Color(0xFF3A424D), const Color(0xFFC8D1DD))
          : (const Color(0xFFDDE3EA), const Color(0xFF3F4A58)),
      ComplaintStatus.assigned => dark
          ? (const Color(0xFF1E3A5F), const Color(0xFFAFCBFF))
          : (const Color(0xFFD3E4FF), const Color(0xFF1D4E89)),
      ComplaintStatus.inProgress => dark
          ? (const Color(0xFF4D3B00), const Color(0xFFFFDF8F))
          : (const Color(0xFFFFE29A), const Color(0xFF5B4300)),
      ComplaintStatus.resolved => dark
          ? (const Color(0xFF00423B), const Color(0xFF9FF0E0))
          : (const Color(0xFFB4ECE0), const Color(0xFF00504A)),
      ComplaintStatus.verified => dark
          ? (const Color(0xFF1E4D22), const Color(0xFFA8E6A0))
          : (const Color(0xFFC3EFB5), const Color(0xFF1B5E20)),
      ComplaintStatus.reopened => (
          Theme.of(context).colorScheme.errorContainer,
          Theme.of(context).colorScheme.onErrorContainer,
        ),
      ComplaintStatus.rejected => dark
          ? (const Color(0xFF3B3633), const Color(0xFFCFC8C3))
          : (const Color(0xFFE5E1DE), const Color(0xFF4A4643)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(100)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(status.icon, size: 16, color: foreground),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              status.label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

enum MoonPhase { crescent, half, almostFull, full }

/// An asset-free rendering of the Stitch design's loop moon.
class MoonGraphic extends StatelessWidget {
  const MoonGraphic({required this.phase, this.size = 116, this.orbit = false, super.key});
  final MoonPhase phase;
  final double size;
  final bool orbit;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: _MoonPainter(phase: phase, dark: dark, orbit: orbit),
      ),
    );
  }
}

class _MoonPainter extends CustomPainter {
  const _MoonPainter({required this.phase, required this.dark, required this.orbit});
  final MoonPhase phase;
  final bool dark;
  final bool orbit;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * (orbit ? 0.37 : 0.47);
    final disk = Rect.fromCircle(center: center, radius: radius);
    final brown = dark ? FixPalette.darkPrimary : FixPalette.brownLight;
    final pale = dark ? const Color(0xFF68564B) : const Color(0xFFF2E5DD);

    if (orbit) {
      final orbitPaint = Paint()
        ..color = brown.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      final orbitRect = Rect.fromCircle(center: center, radius: radius * 1.13);
      for (var i = 0; i < 36; i++) {
        canvas.drawArc(orbitRect, i * math.pi / 18, math.pi / 45, false, orbitPaint);
      }
    }

    if (phase == MoonPhase.full) {
      final green = dark ? const Color(0xFFA8E6A0) : FixPalette.green;
      canvas.drawCircle(center, radius, Paint()..color = dark ? FixPalette.darkCard : Colors.white);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = green
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      final checkPaint = Paint()
        ..color = green
        ..strokeWidth = radius * 0.09
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final check = Path()
        ..moveTo(center.dx - radius * 0.32, center.dy)
        ..lineTo(center.dx - radius * 0.08, center.dy + radius * 0.23)
        ..lineTo(center.dx + radius * 0.36, center.dy - radius * 0.25);
      canvas.drawPath(check, checkPaint);
      return;
    }

    canvas.drawCircle(center, radius, Paint()..color = brown);
    canvas.save();
    canvas.clipPath(Path()..addOval(disk));
    final shift = switch (phase) {
      MoonPhase.crescent => -radius * 0.72,
      MoonPhase.half => -radius,
      MoonPhase.almostFull => -radius * 0.22,
      MoonPhase.full => 0.0,
    };
    canvas.drawCircle(center.translate(shift, 0), radius, Paint()..color = pale);
    canvas.restore();
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = brown.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _MoonPainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.dark != dark || oldDelegate.orbit != orbit;
}

class MoonArch extends StatelessWidget {
  const MoonArch({required this.child, this.height = 240, super.key});
  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(18) / 18;
        final extraHeight = (textScale - 1).clamp(0.0, 2.0) * 140;
        final effectiveHeight = height + extraHeight;
        final radius = Radius.elliptical(constraints.maxWidth / 2, effectiveHeight * 0.85);
        return Container(
          width: double.infinity,
          constraints: BoxConstraints(minHeight: effectiveHeight),
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.only(
              topLeft: radius,
              topRight: radius,
              bottomLeft: const Radius.circular(28),
              bottomRight: const Radius.circular(28),
            ),
          ),
          child: child,
        );
      },
    );
  }
}

String formatRelativeTime(DateTime dateTime) {
  final diff = DateTime.now().toUtc().difference(dateTime.toUtc());
  if (diff.isNegative) {
    final ahead = dateTime.toUtc().difference(DateTime.now().toUtc());
    if (ahead.inMinutes < 60) return 'in ${ahead.inMinutes}m';
    if (ahead.inHours < 48) return 'in ${ahead.inHours}h';
    return 'in ${ahead.inDays}d';
  }
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}
