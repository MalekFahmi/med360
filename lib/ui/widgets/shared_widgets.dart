// Shared reusable widgets used across multiple screens.
// Build once, use everywhere — keeps each screen file lean.

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// ─── Badge ────────────────────────────────────────────────────────────────────

enum BadgeVariant { green, amber, red, blue, teal }

class AppBadge extends StatelessWidget {
  final String label;
  final BadgeVariant variant;
  final IconData? icon;

  const AppBadge({
    super.key,
    required this.label,
    this.variant = BadgeVariant.teal,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (variant) {
      BadgeVariant.green => (AppColors.greenLight, AppColors.tealDark),
      BadgeVariant.amber => (AppColors.amberLight, AppColors.amber),
      BadgeVariant.red   => (AppColors.redLight,   AppColors.red),
      BadgeVariant.blue  => (AppColors.blueLight,  AppColors.blue),
      BadgeVariant.teal  => (AppColors.tealLight,  AppColors.tealDark),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.pill),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: fg),
            const SizedBox(width: 3),
          ],
          Text(label, style: AppTextStyles.badgeText.copyWith(color: fg)),
        ],
      ),
    );
  }

  // Convenience factory based on adherence label
  factory AppBadge.adherence(String label) {
    final variant = switch (label) {
      'Good' || 'جيد'     => BadgeVariant.green,
      'Fair' || 'مقبول'   => BadgeVariant.amber,
      _                   => BadgeVariant.red,
    };
    return AppBadge(label: label, variant: variant);
  }
}

// ─── Card wrapper ─────────────────────────────────────────────────────────────

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final inner = Padding(
      padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
      child: child,
    );
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: AppRadius.lg,
        border: Border.all(color: Colors.black.withOpacity(0.07)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: onTap != null
          ? InkWell(onTap: onTap, borderRadius: AppRadius.lg, child: inner)
          : inner,
    );
  }
}

// ─── Medication colour / icon helper ─────────────────────────────────────────

class MedIconBubble extends StatelessWidget {
  final String medicationId;
  final double size;

  const MedIconBubble({super.key, required this.medicationId, this.size = 44});

  static (Color bg, Color fg, IconData icon) _style(String id) =>
      switch (id) {
        'MED-001' => (AppColors.tealLight,  AppColors.tealDark, Icons.medication_rounded),
        'MED-002' => (AppColors.amberLight, AppColors.amber,    Icons.monitor_heart_rounded),
        'MED-003' => (AppColors.blueLight,  AppColors.blue,     Icons.medication_liquid_rounded),
        _          => (AppColors.grayLight,  AppColors.grayMid,  Icons.medication_rounded),
      };

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = _style(medicationId);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.md),
      child: Icon(icon, color: fg, size: size * 0.5),
    );
  }
}

// ─── Progress bar ─────────────────────────────────────────────────────────────

class AdherenceBar extends StatelessWidget {
  final double rate; // 0.0 – 1.0
  final double height;

  const AdherenceBar({super.key, required this.rate, this.height = 8});

  Color get _color {
    final pct = rate * 100;
    if (pct >= 80) return AppColors.teal;
    if (pct >= 60) return AppColors.amber;
    return AppColors.red;
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: AppRadius.pill,
    child: LinearProgressIndicator(
      value: rate,
      minHeight: height,
      backgroundColor: AppColors.grayLight,
      valueColor: AlwaysStoppedAnimation(_color),
    ),
  );
}

// ─── Section label ────────────────────────────────────────────────────────────

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Text(text.toUpperCase(), style: AppTextStyles.sectionLabel),
  );
}

// ─── Loading skeleton ─────────────────────────────────────────────────────────

class SkeletonBox extends StatefulWidget {
  final double height;
  final double? width;
  final BorderRadius? radius;

  const SkeletonBox({
    super.key,
    required this.height,
    this.width,
    this.radius,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween(begin: 0.4, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _anim,
    child: Container(
      height: widget.height,
      width: widget.width ?? double.infinity,
      decoration: BoxDecoration(
        color: AppColors.grayLight,
        borderRadius: widget.radius ?? AppRadius.sm,
      ),
    ),
  );
}

// ─── Metric tile ──────────────────────────────────────────────────────────────

class MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.valueColor = AppColors.grayDark,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.grayLight,
      borderRadius: AppRadius.md,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.metricLabel),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTextStyles.metricValue.copyWith(
            fontSize: 22,
            color: valueColor,
          ),
        ),
      ],
    ),
  );
}

// ─── Toggle row ───────────────────────────────────────────────────────────────

class ToggleRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const ToggleRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 14)),
              if (subtitle != null)
                Text(subtitle!, style: AppTextStyles.medDetail),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: AppColors.teal,
        ),
      ],
    ),
  );
}

// ─── Dose action button ───────────────────────────────────────────────────────

enum DoseButtonState { pending, taken, missed }

class DoseActionButton extends StatelessWidget {
  final DoseButtonState state;
  final VoidCallback? onTake;
  final VoidCallback? onMiss;

  const DoseActionButton({
    super.key,
    required this.state,
    this.onTake,
    this.onMiss,
  });

  @override
  Widget build(BuildContext context) => switch (state) {
    DoseButtonState.taken => _chip(
        label: 'Taken',
        icon: Icons.check_rounded,
        bg: AppColors.greenLight,
        fg: AppColors.tealDark,
      ),
    DoseButtonState.missed => _chip(
        label: 'Missed',
        icon: Icons.close_rounded,
        bg: AppColors.redLight,
        fg: AppColors.red,
      ),
    DoseButtonState.pending => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            onPressed: onTake,
            icon: const Icon(Icons.check_rounded, size: 14),
            label: const Text('Take', style: TextStyle(fontSize: 12)),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.teal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 6),
          OutlinedButton.icon(
            onPressed: onMiss,
            icon: const Icon(Icons.close_rounded, size: 14),
            label: const Text('Miss', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.red,
              side: const BorderSide(color: AppColors.red),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
  };

  Widget _chip({
    required String label,
    required IconData icon,
    required Color bg,
    required Color fg,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: bg, borderRadius: AppRadius.pill),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w500, color: fg)),
          ],
        ),
      );
}

// ─── Info banner (sync / alert) ───────────────────────────────────────────────

class InfoBanner extends StatelessWidget {
  final String message;
  final Color color;
  final IconData icon;

  const InfoBanner({
    super.key,
    required this.message,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: AppRadius.md,
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: TextStyle(fontSize: 12, color: color),
          ),
        ),
      ],
    ),
  );
}