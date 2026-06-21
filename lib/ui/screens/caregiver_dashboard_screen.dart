import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/caregiver_provider.dart';
import '../i18n/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_patient_card.dart';
import '../widgets/shared_report_widgets.dart';
import '../widgets/shared_widgets.dart';
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
    final strings = AppStrings.of(context);
    final isArabic = strings.isArabic;
    final caregiver = auth.caregiver;
    final reports = provider.sharedReports
        .where((report) => report['archived'] != true)
        .toList();

    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
          backgroundColor: AppColors.pageTint,
          appBar: AppBar(
            title: Text(strings.pick('لوحة المرافق', 'Caregiver dashboard')),
            actions: [
              IconButton(
                tooltip: strings.logout,
                onPressed: () => context.read<AuthProvider>().logout(),
                icon: const Icon(Icons.logout_rounded),
              ),
            ],
            bottom: TabBar(
              tabs: [
                Tab(
                    icon: const Icon(Icons.people_outline),
                    text: strings.patients),
                Tab(
                    icon: const Icon(Icons.summarize_outlined),
                    text: strings.reports),
                Tab(
                    icon: const Icon(Icons.notifications_outlined),
                    text: strings.notifications),
              ],
            ),
          ),
          body: RefreshIndicator(
            onRefresh: _load,
            child: TabBarView(
              children: [
                _PatientsTab(
                  caregiverName: caregiver?.name ?? strings.caregiver,
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
    final strings = AppStrings.of(context);
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
                label: strings.patients,
                value: '${patients.length}',
                valueColor: AppColors.teal,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: MetricTile(
                label: strings.notifications,
                value: '$unreadCount',
                valueColor: unreadCount > 0 ? AppColors.red : AppColors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        MetricTile(
          label: strings.sharedReports,
          value: '$reportsCount',
          valueColor: AppColors.sky,
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
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: Text(strings.add),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (patients.isEmpty)
          EmptyState(
            icon: Icons.people_outline_rounded,
            title: strings.noPatients,
            subtitle: strings.noPatientsCaregiverHint,
          )
        else
          ...patients.map(
            (patient) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: SharedPatientCard(
                patient: patient,
                actorRole: 'caregiver',
              ),
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
    final strings = AppStrings.of(context);
    if (reports.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          EmptyState(
            icon: Icons.summarize_outlined,
            title: strings.noSharedReports,
            subtitle: strings.sharedReportsHint,
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
    final strings = AppStrings.of(context);
    if (notifications.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          EmptyState(
            icon: Icons.notifications_outlined,
            title: strings.noNotifications,
            subtitle: strings.pick(
              'ستظهر هنا تنبيهات الجرعات الفائتة.',
              'Missed-dose alerts will appear here.',
            ),
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
  final strings = AppStrings.of(context);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        ok
            ? strings.pick('تمت إضافة المريض', 'Patient added')
            : strings.pick('تعذرت إضافة المريض', 'Could not add patient'),
      ),
      backgroundColor: ok ? AppColors.teal : AppColors.red,
      behavior: SnackBarBehavior.floating,
    ),
  );
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
                  ? AppStrings.of(context).pick('تنبيه جديد', 'New alert')
                  : AppStrings.of(context).pick(
                      'تنبيه جرعة: ${notification.medicationName}',
                      'Dose alert: ${notification.medicationName}',
                    ),
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
    final strings = AppStrings.of(context);
    Navigator.pop(
      context,
      _PatientAction(
        createNew: _createNew,
        name: _nameCtrl.text.trim().isEmpty
            ? strings.patient
            : _nameCtrl.text.trim(),
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
    final strings = AppStrings.of(context);
    final isArabic = strings.isArabic;
    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
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
                    strings.addPatient,
                    style: AppTextStyles.screenTitle.copyWith(fontSize: 24),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                        value: true,
                        label: Text(strings.create),
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                      ),
                      ButtonSegment(
                        value: false,
                        label: Text(strings.link),
                        icon: const Icon(Icons.link_rounded),
                      ),
                    ],
                    selected: {_createNew},
                    onSelectionChanged: (value) =>
                        setState(() => _createNew = value.first),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (_createNew) ...[
                    _field(
                      _nameCtrl,
                      strings.pick('اسم المريض', 'Patient name'),
                      Icons.person_outline,
                    ),
                    _field(
                      _emailCtrl,
                      strings.pick('بريد المريض', 'Patient email'),
                      Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) =>
                          value == null || !value.contains('@')
                              ? strings.pick(
                                  'أدخل بريد صحيح', 'Enter a valid email')
                              : null,
                    ),
                    _field(
                      _passwordCtrl,
                      strings.pick('كلمة المرور', 'Password'),
                      Icons.lock_outline_rounded,
                      obscure: true,
                      validator: (value) => value == null || value.length < 6
                          ? strings.pick(
                              'كلمة المرور 6 أحرف على الأقل',
                              'Password must be at least 6 characters',
                            )
                          : null,
                    ),
                  ],
                  _field(
                    _phoneCtrl,
                    _createNew
                        ? strings.pick('هاتف المريض', 'Patient phone')
                        : strings.pick(
                            'هاتف المريض الحالي',
                            'Existing patient phone',
                          ),
                    Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                  ),
                  if (_createNew)
                    _field(
                      _conditionCtrl,
                      strings.pick(
                        'الحالة المزمنة (اختياري)',
                        'Chronic condition (optional)',
                      ),
                      Icons.medical_information_outlined,
                      required: false,
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.check_rounded),
                    label: Text(
                      _createNew
                          ? strings.pick('إنشاء المريض', 'Create patient')
                          : strings.linkPatient,
                    ),
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
                ? AppStrings.of(context).pick(
                    'هذا الحقل مطلوب',
                    'This field is required',
                  )
                : null,
      ),
    );
  }
}
