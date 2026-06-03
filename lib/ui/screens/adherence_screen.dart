import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../services/firebase_backend_service.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';

class AdherenceScreen extends StatelessWidget {
  const AdherenceScreen({super.key});

  Future<void> _shareReport(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final reportProvider = context.read<ReportProvider>();
    final patient = auth.patient;
    if (patient == null || reportProvider.currentMonthReport == null) return;

    final reportType = await _chooseReportType(context);
    if (reportType == null || !context.mounted) return;

    final recipient = await showModalBottomSheet<_ReportRecipient>(
      context: context,
      useSafeArea: true,
      builder: (_) => _ReportShareSheet(
        caregivers: auth.caregivers,
        doctors: auth.linkedDoctors,
      ),
    );
    if (recipient == null || !context.mounted) return;

    final shared = await reportProvider.shareCurrentReport(
      patientId: patient.id,
      patientName: patient.name,
      recipientRole: recipient.role,
      recipientId: recipient.id,
      reportType: reportType,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(shared
            ? 'تمت مشاركة التقرير مع ${recipient.name}'
            : 'لا توجد بيانات لهذا التقرير'),
        backgroundColor: shared ? AppColors.teal : AppColors.amber,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _exportPdf(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final reportProvider = context.read<ReportProvider>();
    final patient = auth.patient;
    if (patient == null) return;

    final reportType = await _chooseReportType(context);
    if (reportType == null || !context.mounted) return;

    final bytes = reportProvider.exportCurrentMonthPdfBytes(
      patientName: patient.name,
      reportType: reportType,
    );
    if (bytes == null) return;

    final fileName =
        'med360-${patient.name.trim().replaceAll(RegExp(r"\s+"), "-")}-$reportType-report.pdf';
    await Share.shareXFiles(
      [
        XFile.fromData(
          bytes,
          name: fileName,
          mimeType: 'application/pdf',
        ),
      ],
      subject: 'Med360 report',
      text: 'Med360 report for ${patient.name}',
    );
    await FirebaseBackendService().logUserEngagementEvent(
      patientId: patient.id,
      eventType: 'reportPdfExported',
      source: 'patient',
      details: {
        'fileName': fileName,
        'bytes': bytes.lengthInBytes,
        'reportType': reportType,
      },
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم تجهيز تقرير PDF للمشاركة'),
        backgroundColor: AppColors.teal,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _uploadReport(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final patient = auth.patient;
    if (patient == null) return;

    final recipient = await showModalBottomSheet<_ReportRecipient>(
      context: context,
      useSafeArea: true,
      builder: (_) => _ReportShareSheet(
        caregivers: auth.caregivers,
        doctors: auth.linkedDoctors,
      ),
    );
    if (recipient == null || !context.mounted) return;

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg', 'doc', 'docx'],
      withData: true,
    );
    if (picked == null || picked.files.single.bytes == null) return;

    final file = picked.files.single;
    await FirebaseBackendService().uploadPatientReport(
      patientId: patient.id,
      patientName: patient.name,
      recipientRole: recipient.role,
      recipientId: recipient.id,
      fileName: file.name,
      bytes: file.bytes!,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم رفع ${file.name} إلى ${recipient.name}'),
        backgroundColor: AppColors.teal,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<String?> _chooseReportType(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('اختر نوع التقرير'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'daily'),
            child: const Text('تقرير يومي'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'weekly'),
            child: const Text('تقرير أسبوعي'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'monthly'),
            child: const Text('تقرير شهري'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reportProvider = context.watch<ReportProvider>();
    final current = reportProvider.currentMonthReport;
    final past = reportProvider.pastReports;

    return Scaffold(
      backgroundColor: AppColors.pageTint,
      appBar: AppBar(title: const Text('التقارير')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
        children: [
          if (current == null)
            const EmptyState(
              icon: Icons.bar_chart_rounded,
              title: 'لا يوجد تقرير حالياً',
              subtitle: 'سيظهر التقرير بعد تسجيل جرعاتك',
            )
          else ...[
            _ReportSummaryCard(report: current),
            const SizedBox(height: AppSpacing.lg),
            _ReportActions(
              onShare: () => _shareReport(context),
              onExport: () => _exportPdf(context),
              onUpload: () => _uploadReport(context),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          Text(
            'تقارير سابقة',
            style: AppTextStyles.screenTitle.copyWith(fontSize: 22),
          ),
          const SizedBox(height: AppSpacing.md),
          if (past.isEmpty)
            const AppCard(
              child: Text(
                'لا توجد تقارير سابقة بعد',
                style: AppTextStyles.medName,
              ),
            )
          else
            ...past.map(
              (report) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _PastReportTile(report: report),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReportSummaryCard extends StatelessWidget {
  final MonthlyAdherenceSummary report;

  const _ReportSummaryCard({required this.report});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            report.monthLabelAr,
            style: AppTextStyles.screenTitle.copyWith(fontSize: 24),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _ReportMetric(
                  label: 'الالتزام',
                  value: report.overallPercentage,
                  color: AppColors.teal,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _ReportMetric(
                  label: 'مأخوذة',
                  value: '${report.takenDoses}',
                  color: AppColors.green,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _ReportMetric(
                  label: 'فائتة',
                  value: '${report.missedDoses}',
                  color: AppColors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          AdherenceBar(rate: report.overallAdherenceRate, height: 14),
        ],
      ),
    );
  }
}

class _ReportMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _ReportMetric({
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
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.medDetail),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTextStyles.screenTitle.copyWith(
              color: color,
              fontSize: 22,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportActions extends StatelessWidget {
  final VoidCallback onShare;
  final VoidCallback onExport;
  final VoidCallback onUpload;

  const _ReportActions({
    required this.onShare,
    required this.onExport,
    required this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onShare,
              icon: const Icon(Icons.ios_share_rounded),
              label: const Text('مشاركة التقرير'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onExport,
              icon: const Icon(Icons.picture_as_pdf_rounded),
              label: const Text('تصدير PDF'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onUpload,
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('رفع ملف'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PastReportTile extends StatelessWidget {
  final MonthlyAdherenceSummary report;

  const _PastReportTile({required this.report});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Text(report.monthLabelAr, style: AppTextStyles.medName),
          ),
          Text(
            report.overallPercentage,
            style: AppTextStyles.screenTitle.copyWith(
              color: AppColors.teal,
              fontSize: 22,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportRecipient {
  final String id;
  final String name;
  final String role;

  const _ReportRecipient({
    required this.id,
    required this.name,
    required this.role,
  });
}

class _ReportShareSheet extends StatelessWidget {
  final List<Caregiver> caregivers;
  final List<DoctorUser> doctors;

  const _ReportShareSheet({
    required this.caregivers,
    required this.doctors,
  });

  @override
  Widget build(BuildContext context) {
    final hasRecipients = caregivers.isNotEmpty || doctors.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'مشاركة التقرير',
            style: AppTextStyles.screenTitle.copyWith(fontSize: 24),
          ),
          const SizedBox(height: AppSpacing.md),
          if (!hasRecipients)
            const EmptyState(
              icon: Icons.group_add_outlined,
              title: 'لا يوجد مستلمون',
              subtitle: 'اربط مرافقاً أو طبيباً قبل مشاركة التقارير',
            )
          else ...[
            if (doctors.isNotEmpty) ...[
              const SectionLabel('الأطباء'),
              ...doctors.map(
                (doctor) => ListTile(
                  leading: const Icon(Icons.local_hospital_outlined),
                  title: Text(doctor.name),
                  subtitle: Text(doctor.specialty),
                  onTap: () => Navigator.pop(
                    context,
                    _ReportRecipient(
                      id: doctor.uid,
                      name: doctor.name,
                      role: 'doctor',
                    ),
                  ),
                ),
              ),
            ],
            if (caregivers.isNotEmpty) ...[
              const SectionLabel('المرافقون'),
              ...caregivers.map(
                (caregiver) => ListTile(
                  leading: const Icon(Icons.health_and_safety_outlined),
                  title: Text(caregiver.name),
                  subtitle: Text(caregiver.email ?? caregiver.phone),
                  onTap: () => Navigator.pop(
                    context,
                    _ReportRecipient(
                      id: caregiver.id,
                      name: caregiver.name,
                      role: 'caregiver',
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
