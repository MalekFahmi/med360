import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/providers.dart';
import '../../services/firebase_backend_service.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';
import 'shared_patient_medications_screen.dart';

class DoctorDashboardScreen extends StatefulWidget {
  const DoctorDashboardScreen({super.key});

  @override
  State<DoctorDashboardScreen> createState() => _DoctorDashboardScreenState();
}

class _DoctorDashboardScreenState extends State<DoctorDashboardScreen> {
  List<Map<String, dynamic>> _patients = const [];
  List<Map<String, dynamic>> _reports = const [];
  List<Map<String, dynamic>> _inbox = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPatients());
  }

  Future<void> _loadPatients() async {
    final doctor = context.read<AuthProvider>().doctor;
    if (doctor == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    List<Map<String, dynamic>> patients = const [];
    List<Map<String, dynamic>> reports = const [];
    List<Map<String, dynamic>> inbox = const [];
    try {
      await FirebaseBackendService().logUserEngagementEvent(
        eventType: 'dailyAppUsage',
        source: 'appOpen',
        details: {
          'role': 'doctor',
          'openedAt': DateTime.now().toIso8601String(),
        },
      );
      patients = await FirebaseBackendService().fetchAssignedPatientsForDoctor(
        doctor.uid,
      );
      reports = await FirebaseBackendService().fetchSharedReportsForRecipient(
        recipientId: doctor.uid,
        recipientRole: 'doctor',
      );
      inbox = await FirebaseBackendService().fetchDoctorInbox(doctor.uid);
    } catch (e) {
      debugPrint('Doctor dashboard load skipped: $e');
    }
    if (!mounted) return;
    setState(() {
      _patients = patients;
      _reports = reports;
      _inbox = inbox;
      _loading = false;
    });
  }

  Future<void> _reviewReport(String reportId) async {
    await FirebaseBackendService().markReportReviewed(reportId);
    await _loadPatients();
  }

  Future<void> _archiveReport(String reportId) async {
    await FirebaseBackendService().archiveReport(reportId);
    await _loadPatients();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final doctor = auth.doctor;

    return Scaffold(
      backgroundColor: AppColors.grayLight,
      appBar: AppBar(
        title: const Text('Doctor Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => context.read<AuthProvider>().logout(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          AppCard(
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    color: AppColors.teal,
                    borderRadius: AppRadius.md,
                  ),
                  child: const Icon(
                    Icons.local_hospital_outlined,
                    color: AppColors.white,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        doctor?.name ?? 'Doctor',
                        style: AppTextStyles.screenTitle.copyWith(fontSize: 18),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        doctor?.specialty.isNotEmpty == true
                            ? doctor!.specialty
                            : 'Medical care team',
                        style: AppTextStyles.screenSub,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionLabel('Assigned patients'),
          const SizedBox(height: AppSpacing.sm),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_patients.isEmpty)
            const EmptyState(
              icon: Icons.people_alt_outlined,
              title: 'No assigned patients',
              subtitle:
                  'Patients can assign you from their Care Team screen using your registered email.',
            )
          else
            ..._patients.map(
              (patient) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _PatientTile(patient: patient),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          _MetricCard(
            icon: Icons.summarize_outlined,
            title: 'Reports',
            value: '${_reports.where((r) => r['archived'] != true).length}',
            subtitle: 'Shared adherence reports ready for review.',
          ),
          const SizedBox(height: AppSpacing.md),
          const SectionLabel('Recent reports'),
          if (_reports.where((r) => r['archived'] != true).isEmpty)
            const EmptyState(
              icon: Icons.summarize_outlined,
              title: 'No shared reports',
              subtitle: 'Reports shared by patients will appear here.',
            )
          else
            ..._reports
                .where((report) => report['archived'] != true)
                .take(5)
                .map(
                  (report) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: _ReportTile(
                      report: report,
                      onReview: () => _reviewReport(report['id']),
                      onArchive: () => _archiveReport(report['id']),
                    ),
                  ),
                ),
          const SizedBox(height: AppSpacing.md),
          _TrendComparisonCard(reports: _reports),
          const SizedBox(height: AppSpacing.md),
          const _MetricCard(
            icon: Icons.inventory_2_outlined,
            title: 'Refill risk',
            value: 'Tracked',
            subtitle: 'Refill alerts for assigned patients appear below.',
          ),
          const SizedBox(height: AppSpacing.md),
          const SectionLabel('Refill risk alerts'),
          if (_inbox.where((item) => item['type'] == 'refillAlert').isEmpty)
            const EmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'No refill risks',
              subtitle: 'Medication inventory alerts will appear here.',
            )
          else
            ..._inbox
                .where((item) => item['type'] == 'refillAlert')
                .take(5)
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: _InboxTile(item: item),
                  ),
                ),
        ],
      ),
    );
  }
}

class _InboxTile extends StatelessWidget {
  final Map<String, dynamic> item;

  const _InboxTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: AppColors.amberLight,
            foregroundColor: AppColors.amber,
            child: Icon(Icons.inventory_2_outlined),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['title'] ?? 'Refill reminder',
                  style: AppTextStyles.medName,
                ),
                const SizedBox(height: 4),
                Text(item['body'] ?? '', style: AppTextStyles.medDetail),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  final Map<String, dynamic> report;
  final VoidCallback onReview;
  final VoidCallback onArchive;

  const _ReportTile({
    required this.report,
    required this.onReview,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    final data = (report['report'] as Map?) ?? const {};
    final adherence = ((data['adherenceRate'] as num?) ?? 0) * 100;
    final reviewed = report['reviewedAt'] != null;
    final isUploaded = report['reportType'] == 'uploaded';
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            backgroundColor: AppColors.blueLight,
            foregroundColor: AppColors.blue,
            child: Icon(Icons.summarize_outlined),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  report['patientName'] ?? 'Patient',
                  style: AppTextStyles.medName,
                ),
                const SizedBox(height: 4),
                Text(
                  isUploaded
                      ? 'Uploaded file - ${data['fileName'] ?? data['label'] ?? 'report'}'
                      : '${report['reportType'] ?? 'monthly'} report - ${adherence.round()}% adherence',
                  style: AppTextStyles.medDetail,
                ),
                if (isUploaded && data['sizeBytes'] != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${(((data['sizeBytes'] as num?) ?? 0) / 1024).toStringAsFixed(1)} KB',
                    style: AppTextStyles.medDetail,
                  ),
                ],
                const SizedBox(height: 8),
                AppBadge(
                  label: reviewed ? 'Reviewed' : 'New',
                  variant: reviewed ? BadgeVariant.green : BadgeVariant.amber,
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'review') onReview();
              if (value == 'archive') onArchive();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'review', child: Text('Mark reviewed')),
              PopupMenuItem(value: 'archive', child: Text('Archive')),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrendComparisonCard extends StatelessWidget {
  final List<Map<String, dynamic>> reports;

  const _TrendComparisonCard({required this.reports});

  @override
  Widget build(BuildContext context) {
    final trendRows = _trendRows();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.show_chart_rounded, color: AppColors.teal),
              SizedBox(width: AppSpacing.sm),
              Text('Trend comparison', style: AppTextStyles.medName),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (trendRows.isEmpty)
            const Text(
              'Share at least two adherence reports to compare trends.',
              style: AppTextStyles.medDetail,
            )
          else
            ...trendRows.map(
              (row) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            row.patientName,
                            style: AppTextStyles.medName.copyWith(fontSize: 14),
                          ),
                        ),
                        AppBadge(
                          label:
                              '${row.firstRate.round()}% -> ${row.latestRate.round()}%',
                          variant: row.delta >= 0
                              ? BadgeVariant.green
                              : BadgeVariant.amber,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: AppRadius.sm,
                      child: LinearProgressIndicator(
                        value: (row.latestRate / 100).clamp(0.0, 1.0),
                        minHeight: 8,
                        color: row.latestRate >= 80
                            ? AppColors.teal
                            : AppColors.amber,
                        backgroundColor: AppColors.grayLight,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${row.count} reports, ${row.delta >= 0 ? '+' : ''}${row.delta.toStringAsFixed(1)} point change',
                      style: AppTextStyles.medDetail,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<_TrendRow> _trendRows() {
    final byPatient = <String, List<Map<String, dynamic>>>{};
    for (final report in reports.where(
      (report) =>
          report['archived'] != true && report['reportType'] != 'uploaded',
    )) {
      final patientId = '${report['patientId'] ?? report['patientName']}';
      byPatient.putIfAbsent(patientId, () => []).add(report);
    }

    final rows = <_TrendRow>[];
    for (final entry in byPatient.entries) {
      final patientReports = entry.value
        ..sort((a, b) => '${a['createdAt']}'.compareTo('${b['createdAt']}'));
      if (patientReports.length < 2) continue;
      final first = _rate(patientReports.first);
      final latest = _rate(patientReports.last);
      rows.add(
        _TrendRow(
          patientName: patientReports.last['patientName'] ?? 'Patient',
          firstRate: first,
          latestRate: latest,
          count: patientReports.length,
        ),
      );
    }
    rows.sort((a, b) => a.latestRate.compareTo(b.latestRate));
    return rows.take(4).toList();
  }

  double _rate(Map<String, dynamic> report) {
    final data = (report['report'] as Map?) ?? const {};
    return (((data['adherenceRate'] as num?) ?? 0) * 100).toDouble();
  }
}

class _TrendRow {
  final String patientName;
  final double firstRate;
  final double latestRate;
  final int count;

  const _TrendRow({
    required this.patientName,
    required this.firstRate,
    required this.latestRate,
    required this.count,
  });

  double get delta => latestRate - firstRate;
}

class _PatientTile extends StatelessWidget {
  final Map<String, dynamic> patient;
  const _PatientTile({required this.patient});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SharedPatientMedicationsScreen(
            patient: patient,
            actorRole: 'doctor',
          ),
        ),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: AppColors.tealLight,
            foregroundColor: AppColors.tealDark,
            child: Icon(Icons.person_outline_rounded),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  patient['name'] ?? 'Patient',
                  style: AppTextStyles.medName,
                ),
                Text(patient['phone'] ?? '', style: AppTextStyles.medDetail),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.grayMid),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String subtitle;

  const _MetricCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Icon(icon, color: AppColors.teal),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.medName),
                const SizedBox(height: 4),
                Text(subtitle, style: AppTextStyles.screenSub),
              ],
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.teal,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
