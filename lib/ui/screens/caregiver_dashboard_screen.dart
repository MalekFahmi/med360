import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/caregiver_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';
import 'shared_patient_medications_screen.dart';
import 'shared_report_detail_screen.dart';

class CaregiverDashboardScreen extends StatefulWidget {
  const CaregiverDashboardScreen({super.key});

  @override
  State<CaregiverDashboardScreen> createState() =>
      _CaregiverDashboardScreenState();
}

class _CaregiverDashboardScreenState extends State<CaregiverDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final uid = context.read<AuthProvider>().caregiver?.uid;
    if (uid == null) return;
    context.read<CaregiverProvider>().listenToCaregiverData(uid);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final provider = context.watch<CaregiverProvider>();
    final caregiver = auth.caregiver;
    final reports = provider.sharedReports
        .where((report) => report['archived'] != true)
        .toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
          backgroundColor: AppColors.pageTint,
          appBar: AppBar(
            title: const Text('لوحة المرافق'),
            actions: [
              IconButton(
                tooltip: 'تسجيل الخروج',
                onPressed: () => context.read<AuthProvider>().logout(),
                icon: const Icon(Icons.logout_rounded),
              ),
            ],
            bottom: const TabBar(
              tabs: [
                Tab(icon: Icon(Icons.people_outline), text: 'المرضى'),
                Tab(icon: Icon(Icons.summarize_outlined), text: 'التقارير'),
                Tab(
                    icon: Icon(Icons.notifications_outlined),
                    text: 'التنبيهات'),
              ],
            ),
          ),
          body: RefreshIndicator(
            onRefresh: _load,
            child: TabBarView(
              children: [
                _PatientsTab(
                  caregiverName: caregiver?.name ?? 'مرافق',
                  caregiverEmail: caregiver?.email ?? '',
                  patients: provider.linkedPatients,
                  unreadCount: provider.unreadCount,
                  reportsCount: reports.length,
                  onAdd: () => _openPatientAction(context),
                ),
                _ReportsTab(
                  reports: reports,
                  onReview: provider.markReportReviewed,
                  onArchive: provider.archiveReport,
                ),
                _NotificationsTab(notifications: provider.notifications),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PatientsTab extends StatelessWidget {
  final String caregiverName;
  final String caregiverEmail;
  final List<Map<String, dynamic>> patients;
  final int unreadCount;
  final int reportsCount;
  final VoidCallback onAdd;

  const _PatientsTab({
    required this.caregiverName,
    required this.caregiverEmail,
    required this.patients,
    required this.unreadCount,
    required this.reportsCount,
    required this.onAdd,
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
                radius: 30,
                backgroundColor: AppColors.tealLight,
                child: Icon(
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
                      caregiverName,
                      style: AppTextStyles.screenTitle.copyWith(fontSize: 23),
                    ),
                    const SizedBox(height: 4),
                    Text(caregiverEmail, style: AppTextStyles.medDetail),
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
                label: 'تنبيهات',
                value: '$unreadCount',
                valueColor: unreadCount > 0 ? AppColors.red : AppColors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        MetricTile(
          label: 'تقارير مشتركة',
          value: '$reportsCount',
          valueColor: AppColors.sky,
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
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('إضافة'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (patients.isEmpty)
          const EmptyState(
            icon: Icons.people_outline_rounded,
            title: 'لا يوجد مرضى',
            subtitle: 'أضف مريضا أو اربطه برقم الهاتف',
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
            title: 'لا توجد تقارير مشتركة',
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

class _NotificationsTab extends StatelessWidget {
  final List<CaregiverNotification> notifications;

  const _NotificationsTab({required this.notifications});

  @override
  Widget build(BuildContext context) {
    if (notifications.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          EmptyState(
            icon: Icons.notifications_outlined,
            title: 'لا توجد تنبيهات',
            subtitle: 'ستظهر هنا تنبيهات الجرعات الفائتة.',
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: notifications
          .take(30)
          .map(
            (notification) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _NotificationCard(notification: notification),
            ),
          )
          .toList(),
    );
  }
}

Future<void> _openPatientAction(BuildContext context) async {
  final action = await showModalBottomSheet<_PatientAction>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => const _PatientActionSheet(),
  );
  if (action == null || !context.mounted) return;
  final provider = context.read<CaregiverProvider>();
  final caregiverUid = context.read<AuthProvider>().caregiver?.uid;
  final ok = action.createNew
      ? await provider.createManagedPatient(
          name: action.name,
          email: action.email,
          password: action.password,
          phone: action.phone,
          chronicCondition: action.chronicCondition,
        )
      : await provider.linkExistingPatientByPhone(action.phone);
  if (ok && caregiverUid != null) {
    provider.listenToCaregiverData(caregiverUid);
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(ok ? 'تمت إضافة المريض' : 'تعذرت إضافة المريض'),
      backgroundColor: ok ? AppColors.teal : AppColors.red,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

class _PatientCard extends StatelessWidget {
  final Map<String, dynamic> patient;

  const _PatientCard({required this.patient});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SharedPatientMedicationsScreen(
            patient: patient,
            actorRole: 'caregiver',
          ),
        ),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: AppColors.skyLight,
            child: Icon(Icons.person_rounded, color: AppColors.sky),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${patient['name'] ?? 'مريض'}',
                    style: AppTextStyles.medName),
                const SizedBox(height: 4),
                Text('${patient['phone'] ?? ''}',
                    style: AppTextStyles.medDetail),
              ],
            ),
          ),
          const Icon(Icons.chevron_left_rounded),
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

class _NotificationCard extends StatelessWidget {
  final CaregiverNotification notification;

  const _NotificationCard({required this.notification});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Icon(
            notification.acknowledged
                ? Icons.mark_email_read_outlined
                : Icons.notification_important_outlined,
            color:
                notification.acknowledged ? AppColors.grayMid : AppColors.red,
            size: 30,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              notification.medicationName == null
                  ? 'تنبيه جديد'
                  : 'تنبيه جرعة: ${notification.medicationName}',
              style: AppTextStyles.medName,
            ),
          ),
        ],
      ),
    );
  }
}

class _PatientAction {
  final bool createNew;
  final String name;
  final String email;
  final String password;
  final String phone;
  final String? chronicCondition;

  const _PatientAction({
    required this.createNew,
    required this.name,
    required this.email,
    required this.password,
    required this.phone,
    this.chronicCondition,
  });
}

class _PatientActionSheet extends StatefulWidget {
  const _PatientActionSheet();

  @override
  State<_PatientActionSheet> createState() => _PatientActionSheetState();
}

class _PatientActionSheetState extends State<_PatientActionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _conditionCtrl = TextEditingController();
  bool _createNew = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _phoneCtrl.dispose();
    _conditionCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _PatientAction(
        createNew: _createNew,
        name: _nameCtrl.text.trim().isEmpty ? 'مريض' : _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim().toLowerCase(),
        password: _passwordCtrl.text,
        phone: _phoneCtrl.text.trim(),
        chronicCondition: _conditionCtrl.text.trim().isEmpty
            ? null
            : _conditionCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset + 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'إضافة مريض',
                    style: AppTextStyles.screenTitle.copyWith(fontSize: 24),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: true,
                        label: Text('إنشاء'),
                        icon: Icon(Icons.person_add_alt_1_rounded),
                      ),
                      ButtonSegment(
                        value: false,
                        label: Text('ربط'),
                        icon: Icon(Icons.link_rounded),
                      ),
                    ],
                    selected: {_createNew},
                    onSelectionChanged: (value) =>
                        setState(() => _createNew = value.first),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (_createNew) ...[
                    _field(_nameCtrl, 'اسم المريض', Icons.person_outline),
                    _field(
                      _emailCtrl,
                      'بريد المريض',
                      Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) =>
                          value == null || !value.contains('@')
                              ? 'أدخل بريد صحيح'
                              : null,
                    ),
                    _field(
                      _passwordCtrl,
                      'كلمة المرور',
                      Icons.lock_outline_rounded,
                      obscure: true,
                      validator: (value) => value == null || value.length < 6
                          ? 'كلمة المرور 6 أحرف على الأقل'
                          : null,
                    ),
                  ],
                  _field(
                    _phoneCtrl,
                    _createNew ? 'هاتف المريض' : 'هاتف المريض الحالي',
                    Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                  ),
                  if (_createNew)
                    _field(
                      _conditionCtrl,
                      'الحالة المزمنة (اختياري)',
                      Icons.medical_information_outlined,
                      required: false,
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.check_rounded),
                    label: Text(_createNew ? 'إنشاء المريض' : 'ربط المريض'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool obscure = false,
    bool required = true,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
        validator: validator ??
            (value) => required && (value == null || value.trim().isEmpty)
                ? 'هذا الحقل مطلوب'
                : null,
      ),
    );
  }
}
