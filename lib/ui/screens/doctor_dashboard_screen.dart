import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/providers.dart';
import '../../services/firebase_backend_domains.dart';
import '../../services/firebase_backend_service.dart';
import '../i18n/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_patient_card.dart';
import '../widgets/shared_report_widgets.dart';
import '../widgets/shared_widgets.dart';
import 'shared_report_detail_screen.dart';

class DoctorDashboardScreen extends StatefulWidget {
  const DoctorDashboardScreen({super.key});

  @override
  State<DoctorDashboardScreen> createState() => _DoctorDashboardScreenState();
}

class _DoctorDashboardScreenState extends State<DoctorDashboardScreen> {
  List<Map<String, dynamic>> _patients = const [];
  List<Map<String, dynamic>> _reports = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final doctor = context.read<AuthProvider>().doctor;
    if (doctor == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final patients = await FirebaseBackendService()
          .careTeam
          .fetchAssignedPatientsForDoctor(
            doctor.uid,
          );
      final reports = await FirebaseBackendService().reports.fetchForRecipient(
            recipientId: doctor.uid,
            recipientRole: 'doctor',
          );
      if (!mounted) return;
      setState(() {
        _patients = patients;
        _reports = reports;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Doctor dashboard load skipped: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _linkPatient() async {
    final identifier = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => const _PatientLinkSheet(),
    );
    if (identifier == null || !mounted) return;

    final linked =
        await FirebaseBackendService().careTeam.linkPatientToCurrentDoctor(
              identifier,
            );
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          linked
              ? 'تم ربط المريض بالطبيب'
              : 'لم يتم العثور على مريض بهذا البريد أو الرقم',
        ),
        backgroundColor: linked ? AppColors.teal : AppColors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (linked) await _load();
  }

  Future<void> _reviewReport(String reportId) async {
    if (reportId.isEmpty) return;
    await FirebaseBackendService().reports.markReviewed(reportId);
    await _load();
  }

  Future<void> _archiveReport(String reportId) async {
    if (reportId.isEmpty) return;
    await FirebaseBackendService().reports.archive(reportId);
    await _load();
  }

  Future<void> _restoreReport(String reportId) async {
    if (reportId.isEmpty) return;
    await FirebaseBackendService().reports.restore(reportId);
    await _load();
  }

  Future<void> _unlinkPatient(Map<String, dynamic> patient) async {
    final strings = AppStrings.of(context);
    final patientUid = '${patient['patientUid'] ?? ''}';
    if (patientUid.isEmpty) return;
    final name = '${patient['name'] ?? strings.patient}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.pick('حذف المريض؟', 'Remove patient?')),
        content: Text(
          strings.pick(
            'سيتم حذف $name من لوحة الطبيب فقط، ولن يتم حذف حساب المريض.',
            '$name will be removed from this doctor dashboard only. The patient account will not be deleted.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(strings.pick('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: Text(strings.pick('حذف', 'Remove')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await FirebaseBackendService()
        .careTeam
        .unlinkCurrentDoctorFromPatient(patientUid: patientUid);
    if (!mounted) return;
    setState(() {
      _patients = _patients
          .where((item) => '${item['patientUid'] ?? ''}' != patientUid)
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final doctor = context.watch<AuthProvider>().doctor;
    final strings = AppStrings.of(context);
    final isArabic = strings.isArabic;
    final visibleReports =
        _reports.where((report) => report['archived'] != true).toList();
    final archivedReports =
        _reports.where((report) => report['archived'] == true).toList();

    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
          backgroundColor: AppColors.pageTint,
          appBar: AppBar(
            title: Text(strings.pick('لوحة الطبيب', 'Doctor dashboard')),
            actions: [
              IconButton(
                tooltip: strings.logout,
                icon: const Icon(Icons.logout_rounded),
                onPressed: () => context.read<AuthProvider>().logout(),
              ),
            ],
            bottom: TabBar(
              tabs: [
                Tab(
                    icon: const Icon(Icons.people_alt_outlined),
                    text: strings.patients),
                Tab(
                    icon: const Icon(Icons.summarize_outlined),
                    text: strings.reports),
                Tab(
                    icon: const Icon(Icons.archive_outlined),
                    text: strings.pick('الأرشيف', 'Archive')),
              ],
            ),
          ),
          body: RefreshIndicator(
            onRefresh: _load,
            child: TabBarView(
              children: [
                _PatientsTab(
                  loading: _loading,
                  doctorName: doctor?.name ?? strings.doctor,
                  specialty: doctor?.specialty.isNotEmpty == true
                      ? doctor!.specialty
                      : strings.pick('الرعاية الطبية', 'Medical care'),
                  patients: _patients,
                  reportsCount: visibleReports.length,
                  onLink: _linkPatient,
                  onDelete: _unlinkPatient,
                ),
                _ReportsTab(
                  reports: visibleReports,
                  onReview: _reviewReport,
                  onArchive: _archiveReport,
                  onRestore: _restoreReport,
                ),
                _ReportsTab(
                  reports: archivedReports,
                  archived: true,
                  onReview: _reviewReport,
                  onArchive: _archiveReport,
                  onRestore: _restoreReport,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PatientsTab extends StatelessWidget {
  final bool loading;
  final String doctorName;
  final String specialty;
  final List<Map<String, dynamic>> patients;
  final int reportsCount;
  final VoidCallback onLink;
  final ValueChanged<Map<String, dynamic>> onDelete;

  const _PatientsTab({
    required this.loading,
    required this.doctorName,
    required this.specialty,
    required this.patients,
    required this.reportsCount,
    required this.onLink,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        AppCard(
          child: Row(
            children: [
              const CircleAvatar(
                radius: 34,
                backgroundColor: AppColors.teal,
                child: Icon(
                  Icons.local_hospital_outlined,
                  color: AppColors.white,
                  size: 34,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(doctorName, style: AppTextStyles.screenTitle),
                    const SizedBox(height: 6),
                    Text(specialty, style: AppTextStyles.medDetail),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: MetricTile(
                label: strings.patients,
                value: '${patients.length}',
                valueColor: AppColors.teal,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: MetricTile(
                label: strings.reports,
                value: '$reportsCount',
                valueColor: AppColors.sky,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        Row(
          children: [
            Expanded(
              child: Text(
                strings.patients,
                style: AppTextStyles.screenTitle.copyWith(fontSize: 22),
              ),
            ),
            FilledButton.icon(
              onPressed: onLink,
              icon: const Icon(Icons.link_rounded),
              label: Text(strings.linkPatient),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (patients.isEmpty)
          EmptyState(
            icon: Icons.people_alt_outlined,
            title: strings.noPatients,
            subtitle: strings.noPatientsDoctorHint,
          )
        else
          ...patients.map(
            (patient) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: SharedPatientCard(
                patient: patient,
                actorRole: 'doctor',
                footer: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: OutlinedButton.icon(
                    onPressed: () => onDelete(patient),
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: Text(strings.pick('حذف المريض', 'Remove')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.red,
                      side: const BorderSide(color: AppColors.red),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ReportsTab extends StatelessWidget {
  final List<Map<String, dynamic>> reports;
  final bool archived;
  final ValueChanged<String> onReview;
  final ValueChanged<String> onArchive;
  final ValueChanged<String> onRestore;

  const _ReportsTab({
    required this.reports,
    this.archived = false,
    required this.onReview,
    required this.onArchive,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    if (reports.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          EmptyState(
            icon: Icons.summarize_outlined,
            title: archived
                ? strings.pick('لا توجد تقارير مؤرشفة', 'No archived reports')
                : strings.noReports,
            subtitle: archived
                ? strings.pick(
                    'ستظهر هنا التقارير التي تقوم بأرشفتها.',
                    'Reports you archive will appear here.',
                  )
                : strings.sharedReportsHint,
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: reports
          .map(
            (report) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: SharedReportCard(
                report: report,
                onOpen: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SharedReportDetailScreen(
                      report: report,
                      onReview: () => onReview('${report['id'] ?? ''}'),
                      onArchive: () => onArchive('${report['id'] ?? ''}'),
                    ),
                  ),
                ),
                onReview: () => onReview('${report['id'] ?? ''}'),
                onArchive: () => onArchive('${report['id'] ?? ''}'),
                onRestore: () => onRestore('${report['id'] ?? ''}'),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _PatientLinkSheet extends StatefulWidget {
  const _PatientLinkSheet();

  @override
  State<_PatientLinkSheet> createState() => _PatientLinkSheetState();
}

class _PatientLinkSheetState extends State<_PatientLinkSheet> {
  final _formKey = GlobalKey<FormState>();
  final _identifierCtrl = TextEditingController();

  @override
  void dispose() {
    _identifierCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, _identifierCtrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final strings = AppStrings.of(context);
    final isArabic = strings.isArabic;

    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset + 20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.linkPatient,
                style: AppTextStyles.screenTitle.copyWith(fontSize: 24),
              ),
              const SizedBox(height: 8),
              Text(
                strings.linkPatientHint,
                style: AppTextStyles.medDetail,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _identifierCtrl,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: strings.pick(
                    'بريد أو هاتف المريض',
                    'Patient email or phone',
                  ),
                  prefixIcon: const Icon(Icons.alternate_email_rounded),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? strings.pick(
                        'أدخل بريد أو هاتف المريض',
                        'Enter the patient email or phone',
                      )
                    : null,
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.link_rounded),
                label: Text(strings.linkPatient),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
