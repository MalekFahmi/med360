import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/providers.dart';
import '../../services/firebase_backend_service.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';
import 'shared_patient_medications_screen.dart';
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
      final patients =
          await FirebaseBackendService().fetchAssignedPatientsForDoctor(
        doctor.uid,
      );
      final reports =
          await FirebaseBackendService().fetchSharedReportsForRecipient(
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
    final phone = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => const _PatientLinkSheet(),
    );
    if (phone == null || !mounted) return;

    final linked =
        await FirebaseBackendService().linkPatientToCurrentDoctorByPhone(
      phone,
    );
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          linked
              ? 'تم ربط المريض بالطبيب'
              : 'لم يتم العثور على مريض بهذا الرقم',
        ),
        backgroundColor: linked ? AppColors.teal : AppColors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (linked) await _load();
  }

  Future<void> _reviewReport(String reportId) async {
    if (reportId.isEmpty) return;
    await FirebaseBackendService().markReportReviewed(reportId);
    await _load();
  }

  Future<void> _archiveReport(String reportId) async {
    if (reportId.isEmpty) return;
    await FirebaseBackendService().archiveReport(reportId);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final doctor = context.watch<AuthProvider>().doctor;
    final visibleReports =
        _reports.where((report) => report['archived'] != true).toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: AppColors.pageTint,
          appBar: AppBar(
            title: const Text('لوحة الطبيب'),
            actions: [
              IconButton(
                tooltip: 'تسجيل الخروج',
                icon: const Icon(Icons.logout_rounded),
                onPressed: () => context.read<AuthProvider>().logout(),
              ),
            ],
            bottom: const TabBar(
              tabs: [
                Tab(icon: Icon(Icons.people_alt_outlined), text: 'المرضى'),
                Tab(icon: Icon(Icons.summarize_outlined), text: 'التقارير'),
              ],
            ),
          ),
          body: RefreshIndicator(
            onRefresh: _load,
            child: TabBarView(
              children: [
                _PatientsTab(
                  loading: _loading,
                  doctorName: doctor?.name ?? 'الطبيب',
                  specialty: doctor?.specialty.isNotEmpty == true
                      ? doctor!.specialty
                      : 'الرعاية الطبية',
                  patients: _patients,
                  reportsCount: visibleReports.length,
                  onLink: _linkPatient,
                ),
                _ReportsTab(
                  reports: visibleReports,
                  onReview: _reviewReport,
                  onArchive: _archiveReport,
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

  const _PatientsTab({
    required this.loading,
    required this.doctorName,
    required this.specialty,
    required this.patients,
    required this.reportsCount,
    required this.onLink,
  });

  @override
  Widget build(BuildContext context) {
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
                label: 'المرضى',
                value: '${patients.length}',
                valueColor: AppColors.teal,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: MetricTile(
                label: 'التقارير',
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
                'المرضى',
                style: AppTextStyles.screenTitle.copyWith(fontSize: 22),
              ),
            ),
            FilledButton.icon(
              onPressed: onLink,
              icon: const Icon(Icons.link_rounded),
              label: const Text('ربط مريض'),
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
          const EmptyState(
            icon: Icons.people_alt_outlined,
            title: 'لا يوجد مرضى',
            subtitle: 'اربط مريضا برقم الهاتف لعرض أدويته وتقاريره.',
          )
        else
          ...patients.map(
            (patient) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _PatientCard(patient: patient),
            ),
          ),
      ],
    );
  }
}

class _ReportsTab extends StatelessWidget {
  final List<Map<String, dynamic>> reports;
  final ValueChanged<String> onReview;
  final ValueChanged<String> onArchive;

  const _ReportsTab({
    required this.reports,
    required this.onReview,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    if (reports.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          EmptyState(
            icon: Icons.summarize_outlined,
            title: 'لا توجد تقارير',
            subtitle: 'ستظهر هنا التقارير التي يشاركها المرضى معك.',
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
              child: _ReportCard(
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
              ),
            ),
          )
          .toList(),
    );
  }
}

class _PatientCard extends StatelessWidget {
  final Map<String, dynamic> patient;

  const _PatientCard({required this.patient});

  @override
  Widget build(BuildContext context) {
    final name = '${patient['name'] ?? 'مريض'}';
    final phone = '${patient['phone'] ?? 'بدون رقم هاتف'}';

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
            radius: 28,
            backgroundColor: AppColors.skyLight,
            child: Icon(Icons.person_rounded, color: AppColors.sky, size: 30),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppTextStyles.medName),
                const SizedBox(height: 6),
                Text(phone, style: AppTextStyles.medDetail),
              ],
            ),
          ),
          const Icon(Icons.chevron_left_rounded, color: AppColors.grayMid),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final Map<String, dynamic> report;
  final VoidCallback onOpen;
  final VoidCallback onReview;
  final VoidCallback onArchive;

  const _ReportCard({
    required this.report,
    required this.onOpen,
    required this.onReview,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    final data = (report['report'] as Map?) ?? const {};
    final adherence = (((data['adherenceRate'] as num?) ?? 0) * 100).round();
    final patientName = '${report['patientName'] ?? 'مريض'}';
    final reviewed = report['reviewed'] == true || report['reviewedAt'] != null;
    final type = '${report['reportType'] ?? data['reportType'] ?? 'monthly'}';

    return AppCard(
      onTap: onOpen,
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: AppColors.tealLight,
            child: Icon(Icons.summarize_outlined, color: AppColors.teal),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(patientName, style: AppTextStyles.medName),
                const SizedBox(height: 4),
                Text(
                  type == 'uploaded'
                      ? '${data['fileName'] ?? data['label'] ?? 'ملف مرفوع'}'
                      : 'معدل الالتزام $adherence%',
                  style: AppTextStyles.medDetail,
                ),
              ],
            ),
          ),
          AppBadge(
            label: reviewed ? 'تمت المراجعة' : 'جديد',
            variant: reviewed ? BadgeVariant.teal : BadgeVariant.amber,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'review') onReview();
              if (value == 'archive') onArchive();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'review', child: Text('تمت المراجعة')),
              PopupMenuItem(value: 'archive', child: Text('أرشفة')),
            ],
          ),
        ],
      ),
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
  final _phoneCtrl = TextEditingController();

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, _phoneCtrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset + 20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'ربط مريض',
                style: AppTextStyles.screenTitle.copyWith(fontSize: 24),
              ),
              const SizedBox(height: 8),
              const Text(
                'أدخل رقم هاتف المريض كما هو مسجل في حسابه.',
                style: AppTextStyles.medDetail,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'رقم هاتف المريض',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'أدخل رقم هاتف المريض'
                    : null,
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.link_rounded),
                label: const Text('ربط المريض'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
