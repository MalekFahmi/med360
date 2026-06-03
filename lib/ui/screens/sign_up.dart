import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';

class SignupScreen extends StatefulWidget {
  final VoidCallback onLoginTap;
  final AccountRole selectedRole;
  final ValueChanged<AccountRole> onRoleChanged;

  const SignupScreen({
    super.key,
    required this.onLoginTap,
    required this.selectedRole,
    required this.onRoleChanged,
  });

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _condCtrl = TextEditingController();
  final _specialtyCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();
  DateTime? _dob;
  bool _obscure = true;

  bool get _caregiverMode => widget.selectedRole == AccountRole.caregiver;
  bool get _doctorMode => widget.selectedRole == AccountRole.doctor;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    _condCtrl.dispose();
    _specialtyCtrl.dispose();
    _licenseCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(1980),
      firstDate: DateTime(1920),
      lastDate: DateTime.now().subtract(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final ok = switch (widget.selectedRole) {
      AccountRole.patient => await auth.signUp(
          name: _nameCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
          password: _passCtrl.text,
          dateOfBirth: _dob,
          chronicCondition:
              _condCtrl.text.trim().isEmpty ? null : _condCtrl.text.trim(),
        ),
      AccountRole.caregiver => await auth.registerCaregiver(
          name: _nameCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          password: _passCtrl.text,
          phone: _phoneCtrl.text.trim(),
        ),
      AccountRole.doctor => await auth.registerDoctor(
          name: _nameCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          password: _passCtrl.text,
          phone: _phoneCtrl.text.trim(),
          specialty: _specialtyCtrl.text.trim(),
          licenseNumber: _licenseCtrl.text.trim().isEmpty
              ? null
              : _licenseCtrl.text.trim(),
        ),
    };
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              context.read<AuthProvider>().errorMessage ?? 'فشل إنشاء الحساب'),
          backgroundColor: AppColors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      backgroundColor: AppColors.pageTint,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SignupHeader(),
                const SizedBox(height: AppSpacing.xl),
                AppCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SegmentedButton<AccountRole>(
                        segments: const [
                          ButtonSegment(
                            value: AccountRole.patient,
                            label: Text('مريض'),
                            icon: Icon(Icons.person_outline_rounded),
                          ),
                          ButtonSegment(
                            value: AccountRole.caregiver,
                            label: Text('مرافق'),
                            icon: Icon(Icons.health_and_safety_outlined),
                          ),
                          ButtonSegment(
                            value: AccountRole.doctor,
                            label: Text('طبيب'),
                            icon: Icon(Icons.local_hospital_outlined),
                          ),
                        ],
                        selected: {widget.selectedRole},
                        onSelectionChanged: (value) =>
                            widget.onRoleChanged(value.first),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _field(
                        controller: _nameCtrl,
                        label: 'الاسم الكامل',
                        icon: Icons.person_outline_rounded,
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'أدخل الاسم'
                                : null,
                      ),
                      if (_caregiverMode || _doctorMode)
                        _field(
                          controller: _emailCtrl,
                          label: 'البريد الإلكتروني',
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) =>
                              value == null || !value.contains('@')
                                  ? 'أدخل بريد صحيح'
                                  : null,
                        ),
                      if (_doctorMode) ...[
                        _field(
                          controller: _specialtyCtrl,
                          label: 'التخصص الطبي',
                          icon: Icons.medical_services_outlined,
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                                  ? 'أدخل التخصص'
                                  : null,
                        ),
                        _field(
                          controller: _licenseCtrl,
                          label: 'رقم الترخيص (اختياري)',
                          icon: Icons.badge_outlined,
                        ),
                      ],
                      _field(
                        controller: _phoneCtrl,
                        label: 'رقم الهاتف',
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                        validator: (value) =>
                            value == null || value.trim().length < 7
                                ? 'أدخل رقم هاتف صحيح'
                                : null,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: TextFormField(
                          controller: _passCtrl,
                          obscureText: _obscure,
                          decoration: InputDecoration(
                            labelText: 'كلمة المرور',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              icon: Icon(_obscure
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'أدخل كلمة المرور';
                            }
                            if (value.length < 6) {
                              return 'كلمة المرور 6 أحرف على الأقل';
                            }
                            return null;
                          },
                        ),
                      ),
                      if (!_caregiverMode && !_doctorMode) ...[
                        OutlinedButton.icon(
                          onPressed: _pickDob,
                          icon: const Icon(Icons.cake_outlined),
                          label: Text(_dob == null
                              ? 'تاريخ الميلاد (اختياري)'
                              : '${_dob!.day}/${_dob!.month}/${_dob!.year}'),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _field(
                          controller: _condCtrl,
                          label: 'الحالة المزمنة (اختياري)',
                          icon: Icons.medical_information_outlined,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      FilledButton(
                        onPressed: auth.isLoading ? null : _submit,
                        child: auth.isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.white,
                                ),
                              )
                            : Text(_doctorMode
                                ? 'إنشاء حساب طبيب'
                                : _caregiverMode
                                    ? 'إنشاء حساب مرافق'
                                    : 'إنشاء حساب'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextButton(
                  onPressed: widget.onLoginTap,
                  child: const Text('لديك حساب؟ تسجيل الدخول'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: validator,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      ),
    );
  }
}

class _SignupHeader extends StatelessWidget {
  const _SignupHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: const BoxDecoration(
            color: AppColors.teal,
            borderRadius: AppRadius.lg,
          ),
          child: const Icon(
            Icons.medication_rounded,
            color: AppColors.white,
            size: 42,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('MED360', style: AppTextStyles.screenTitle.copyWith(fontSize: 30)),
        const SizedBox(height: 4),
        const Text('إنشاء حساب جديد', style: AppTextStyles.screenSub),
      ],
    );
  }
}
