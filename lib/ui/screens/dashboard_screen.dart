import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/providers.dart';
import '../i18n/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  Future<void> _takeDose(BuildContext context, DoseConfirmation dose) async {
    final auth = context.read<AuthProvider>();
    final strings = AppStrings(auth.arabicMode);
    final meds = context.read<MedicationProvider>();
    final didConfirm = await context
        .read<AdherenceProvider>()
        .confirmDoseTaken(dose.id, auth.patient!.id);
    if (!didConfirm) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(strings.doseTooEarly),
          backgroundColor: AppColors.amber,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final medication = meds.findById(dose.medicationId);
    if (medication != null && medication.quantityRemaining > 0) {
      await meds.updateMedication(
        auth.patient!.id,
        medication.copyWith(
          quantityRemaining: medication.quantityRemaining - 1,
        ),
        isArabic: auth.arabicMode,
      );
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(strings.doseLoggedTaken(dose.medicationName)),
        backgroundColor: AppColors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final adherence = context.watch<AdherenceProvider>();
    final medications = context.watch<MedicationProvider>();
    final today = adherence.todaysDoses;
    final pending = today.where((dose) => dose.isPending).toList();
    final taken = today.where((dose) => dose.isTaken).length;
    final missed = today.where((dose) => dose.isMissed).length;
    final total = today.length;
    final progress = total == 0 ? 0.0 : taken / total;
    final currentStreak = adherence.currentStreak;
    final longestStreak = adherence.longestStreak;
    final strings = AppStrings.of(context);

    return Scaffold(
      backgroundColor: AppColors.pageTint,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
          children: [
            _Header(name: auth.patient?.name ?? ''),
            const SizedBox(height: AppSpacing.lg),
            _TodaySummary(
              total: total,
              taken: taken,
              missed: missed,
              progress: progress,
              currentStreak: currentStreak,
              longestStreak: longestStreak,
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              pending.isEmpty ? strings.todaysStatus : strings.remainingDoses,
              style: AppTextStyles.screenTitle.copyWith(fontSize: 24),
            ),
            const SizedBox(height: AppSpacing.md),
            if (adherence.isLoading)
              ...List.generate(
                3,
                (_) => const Padding(
                  padding: EdgeInsets.only(bottom: AppSpacing.md),
                  child: AppCard(
                    child: SkeletonBox(height: 74),
                  ),
                ),
              )
            else if (medications.isEmpty)
              EmptyState(
                icon: Icons.medication_outlined,
                title: strings.noMedicationsYet,
                subtitle: strings.addFirstMedicationHint,
              )
            else if (today.isEmpty)
              EmptyState(
                icon: Icons.event_available_rounded,
                title: strings.noDosesToday,
                subtitle: strings.noDosesTodayHint,
              )
            else if (pending.isEmpty)
              const _DoneForTodayCard()
            else
              ...pending.map(
                (dose) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: _DoseActionCard(
                    dose: dose,
                    canTake: adherence.canConfirmDoseNow(dose),
                    onTake: () => _takeDose(context, dose),
                  ),
                ),
              ),
            if (today.isNotEmpty && pending.length != today.length) ...[
              const SizedBox(height: AppSpacing.xl),
              Text(
                strings.handledDoses,
                style: AppTextStyles.screenTitle.copyWith(fontSize: 22),
              ),
              const SizedBox(height: AppSpacing.md),
              ...today.where((dose) => !dose.isPending).map(
                    (dose) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _CompletedDoseTile(dose: dose),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String name;

  const _Header({required this.name});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      elevation: 0,
      color: AppColors.surfaceMuted,
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(
              color: AppColors.tealLight,
              borderRadius: AppRadius.lg,
            ),
            child: const Icon(
              Icons.health_and_safety_rounded,
              color: AppColors.tealDark,
              size: 32,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.of(context).greeting(name),
                  style: AppTextStyles.screenTitle.copyWith(fontSize: 24),
                ),
                const SizedBox(height: 4),
                Text(
                  AppStrings.of(context).dashboardSubtitle,
                  style: AppTextStyles.screenSub.copyWith(fontSize: 15),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TodaySummary extends StatelessWidget {
  final int total;
  final int taken;
  final int missed;
  final double progress;
  final int currentStreak;
  final int longestStreak;

  const _TodaySummary({
    required this.total,
    required this.taken,
    required this.missed,
    required this.progress,
    required this.currentStreak,
    required this.longestStreak,
  });

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return AppCard(
      padding: const EdgeInsets.all(20),
      borderColor: AppColors.tealLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: AppColors.mint,
                  borderRadius: AppRadius.md,
                ),
                child: const Icon(
                  Icons.task_alt_rounded,
                  color: AppColors.tealDark,
                  size: 28,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  strings.takenOfTotal(taken, total),
                  style: AppTextStyles.screenTitle.copyWith(fontSize: 24),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: AppRadius.pill,
            child: LinearProgressIndicator(
              minHeight: 16,
              value: progress.clamp(0, 1),
              backgroundColor: AppColors.border,
              valueColor: const AlwaysStoppedAnimation(AppColors.teal),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _SummaryNumber(
                  label: strings.taken,
                  value: '$taken',
                  color: AppColors.green,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _SummaryNumber(
                  label: strings.missed,
                  value: '$missed',
                  color: AppColors.amber,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _SummaryNumber(
                  label: strings.rate,
                  value: '${(progress * 100).round()}%',
                  color: AppColors.teal,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.skyLight,
              borderRadius: AppRadius.md,
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.local_fire_department_rounded,
                  color: AppColors.sky,
                  size: 34,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(strings.adherenceStreak,
                          style: AppTextStyles.medName),
                      const SizedBox(height: 3),
                      Text(
                        strings.bestStreak(longestStreak),
                        style: AppTextStyles.medDetail,
                      ),
                    ],
                  ),
                ),
                Text(
                  strings.days(currentStreak),
                  style: AppTextStyles.screenTitle.copyWith(
                    color: AppColors.sky,
                    fontSize: 24,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryNumber extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryNumber({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: AppRadius.md,
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.medDetail.copyWith(fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTextStyles.screenTitle.copyWith(
              color: color,
              fontSize: 22,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _DoseActionCard extends StatelessWidget {
  final DoseConfirmation dose;
  final bool canTake;
  final VoidCallback onTake;

  const _DoseActionCard({
    required this.dose,
    required this.canTake,
    required this.onTake,
  });

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return AppCard(
      padding: const EdgeInsets.all(18),
      borderColor: AppColors.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MedIconBubble(medicationId: dose.medicationId, size: 58),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dose.medicationName,
                      style: AppTextStyles.screenTitle.copyWith(fontSize: 23),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    AppBadge(
                      label: strings.doseTimeValue(dose.scheduledTime),
                      variant: BadgeVariant.blue,
                      icon: Icons.schedule_rounded,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: canTake ? onTake : null,
            icon: const Icon(Icons.check_rounded, size: 24),
            label: Text(canTake ? strings.tookIt : strings.availableSoon),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.teal,
              foregroundColor: AppColors.white,
              disabledBackgroundColor: AppColors.grayLight,
              disabledForegroundColor: AppColors.grayMid,
              minimumSize: const Size.fromHeight(58),
              textStyle: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
              shape: const RoundedRectangleBorder(
                borderRadius: AppRadius.md,
              ),
            ),
          ),
          if (!canTake) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              strings.doseTooEarly,
              style: AppTextStyles.medDetail.copyWith(
                color: AppColors.amber,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CompletedDoseTile extends StatelessWidget {
  final DoseConfirmation dose;

  const _CompletedDoseTile({required this.dose});

  @override
  Widget build(BuildContext context) {
    final color = dose.isTaken ? AppColors.green : AppColors.red;
    final strings = AppStrings.of(context);
    final label = dose.isTaken ? strings.taken : strings.missed;
    final icon = dose.isTaken ? Icons.check_circle_rounded : Icons.cancel;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(dose.medicationName, style: AppTextStyles.medName),
          ),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _DoneForTodayCard extends StatelessWidget {
  const _DoneForTodayCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: AppColors.green,
            size: 42,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              AppStrings.of(context).doneForToday,
              style: const TextStyle(
                color: AppColors.navy,
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
