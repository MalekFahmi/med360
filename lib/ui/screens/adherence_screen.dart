import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../widgets/shared_widgets.dart';
import '../theme/app_theme.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../services/firebase_backend_service.dart';

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

    await reportProvider.shareCurrentReport(
      patientId: patient.id,
      patientName: patient.name,
      recipientRole: recipient.role,
      recipientId: recipient.id,
      reportType: reportType,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Report shared with ${recipient.name}'),
      backgroundColor: AppColors.teal,
      behavior: SnackBarBehavior.floating,
    ));
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
        'med360-${patient.name.trim().replaceAll(RegExp(r"\s+"), "-")}-'
        '$reportType-adherence-report.pdf';
    await Share.shareXFiles(
      [
        XFile.fromData(
          bytes,
          name: fileName,
          mimeType: 'application/pdf',
        ),
      ],
      subject: 'Med360 adherence report',
      text: 'Med360 adherence report for ${patient.name}',
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('PDF report ready to share (${bytes.lengthInBytes} bytes)'),
      backgroundColor: AppColors.teal,
      behavior: SnackBarBehavior.floating,
    ));
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Uploaded ${file.name} to ${recipient.name}'),
      backgroundColor: AppColors.teal,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<String?> _chooseReportType(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Report type'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'daily'),
            child: const Text('Daily report'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'weekly'),
            child: const Text('Weekly report'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'monthly'),
            child: const Text('Monthly report'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final reportProv = context.watch<ReportProvider>();
    final isAr = auth.arabicMode;

    final current = reportProv.currentMonthReport;
    final past = reportProv.pastReports;

    return Scaffold(
      backgroundColor: AppColors.grayLight,
      appBar: AppBar(
        backgroundColor: AppColors.grayLight,
        title: Text(isAr ? 'التقارير والالتزام' : 'Adherence Reports',
            style: AppTextStyles.screenTitle),
        elevation: 0,
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (current != null) ...[
              SectionLabel(isAr ? current.monthLabelAr : current.monthLabel),
              Row(
                children: [
                  Expanded(
                      child: MetricTile(
                          label: isAr ? 'نسبة الالتزام' : 'Adherence',
                          value: current.overallPercentage,
                          valueColor: AppColors.teal)),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                      child: MetricTile(
                          label: isAr ? 'تم أخذها' : 'Doses Taken',
                          value: '${current.takenDoses}',
                          valueColor: AppColors.grayDark)),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                      child: MetricTile(
                          label: isAr ? 'فائتة' : 'Missed',
                          value: '${current.missedDoses}',
                          valueColor: AppColors.red)),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _shareReport(context),
                  icon: const Icon(Icons.ios_share_rounded),
                  label: const Text('Share current report'),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _exportPdf(context),
                  icon: const Icon(Icons.picture_as_pdf_rounded),
                  label: const Text('Export PDF report'),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _uploadReport(context),
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text('Upload report file'),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
            SectionLabel(isAr ? 'تقارير الأشهر السابقة' : 'Past Months'),
            if (past.isEmpty)
              Text(isAr
                  ? 'لا توجد بيانات سابقة.'
                  : 'No past data available yet.')
            else
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: past
                      .map((r) => Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                child: Row(
                                  children: [
                                    Expanded(
                                        flex: 2,
                                        child: Text(
                                            isAr
                                                ? r.monthLabelAr
                                                : r.monthLabel,
                                            style: AppTextStyles.medName)),
                                    Expanded(
                                        flex: 3,
                                        child: AdherenceBar(
                                            rate: r.overallAdherenceRate)),
                                    const SizedBox(width: AppSpacing.md),
                                    Text(r.overallPercentage,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13)),
                                  ],
                                ),
                              ),
                              const Divider(
                                  height: 1, color: AppColors.grayLight),
                            ],
                          ))
                      .toList(),
                ),
              ),
          ],
        ),
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
            'Share report',
            style: AppTextStyles.screenTitle.copyWith(fontSize: 20),
          ),
          const SizedBox(height: AppSpacing.md),
          if (!hasRecipients)
            const EmptyState(
              icon: Icons.group_add_outlined,
              title: 'No recipients yet',
              subtitle:
                  'Link a caregiver or doctor before sharing adherence reports.',
            )
          else ...[
            if (doctors.isNotEmpty) ...[
              const SectionLabel('Doctors'),
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
              const SectionLabel('Caregivers'),
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

