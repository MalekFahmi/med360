import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback onSignupTap;
  final AccountRole selectedRole;
  final ValueChanged<AccountRole> onRoleChanged;

  const LoginScreen({
    super.key,
    required this.onSignupTap,
    required this.selectedRole,
    required this.onRoleChanged,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;

  bool get _usesEmail => widget.selectedRole != AccountRole.patient;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final ok = switch (widget.selectedRole) {
      AccountRole.patient => await auth.login(
          phone: _phoneCtrl.text.trim(),
          password: _passCtrl.text,
        ),
      AccountRole.caregiver => await auth.loginCaregiver(
          email: _emailCtrl.text.trim(),
          password: _passCtrl.text,
        ),
      AccountRole.doctor => await auth.loginDoctor(
          email: _emailCtrl.text.trim(),
          password: _passCtrl.text,
        ),
    };
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(context.read<AuthProvider>().errorMessage ?? 'فشل الدخول'),
          backgroundColor: AppColors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _loginWithGoogle() async {
    final auth = context.read<AuthProvider>();
    final ok = await auth.signInWithGoogle(role: widget.selectedRole);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.errorMessage ?? 'تعذر تسجيل الدخول باستخدام Google'),
          backgroundColor: AppColors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _forgotPassword() async {
    final controller = TextEditingController(text: _emailCtrl.text.trim());
    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إعادة تعيين كلمة المرور'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'البريد الإلكتروني',
            helperText:
                'إعادة التعيين عبر SMS غير مفعلة في إعداد Firebase الحالي.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('إرسال'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (email == null || email.isEmpty || !mounted) return;
    final ok = await context.read<AuthProvider>().sendPasswordReset(email);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'تم إرسال رابط إعادة التعيين إلى البريد.'
              : context.read<AuthProvider>().errorMessage ??
                  'تعذر إرسال رابط إعادة التعيين.',
        ),
        backgroundColor: ok ? AppColors.teal : AppColors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      backgroundColor: AppColors.pageTint,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _AuthLogo(title: 'تسجيل الدخول'),
                  const SizedBox(height: AppSpacing.xl),
                  AppCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _RoleSelector(
                          selected: widget.selectedRole,
                          onChanged: widget.onRoleChanged,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        if (_usesEmail)
                          TextFormField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'البريد الإلكتروني أو رقم الهاتف',
                              prefixIcon: Icon(Icons.account_circle_outlined),
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                    ? 'أدخل البريد الإلكتروني أو رقم الهاتف'
                                    : null,
                          )
                        else
                          TextFormField(
                            controller: _phoneCtrl,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'رقم الهاتف أو البريد الإلكتروني',
                              prefixIcon: Icon(Icons.phone_outlined),
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                    ? 'أدخل رقم الهاتف أو البريد'
                                    : null,
                          ),
                        const SizedBox(height: AppSpacing.md),
                        TextFormField(
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
                          validator: (value) => value == null || value.isEmpty
                              ? 'أدخل كلمة المرور'
                              : null,
                        ),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: TextButton(
                            onPressed: auth.isLoading ? null : _forgotPassword,
                            child: const Text('نسيت كلمة المرور؟'),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        FilledButton(
                          onPressed: auth.isLoading ? null : _login,
                          child: auth.isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.white,
                                  ),
                                )
                              : const Text('دخول'),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        OutlinedButton.icon(
                          onPressed: auth.isLoading ? null : _loginWithGoogle,
                          icon: const Icon(Icons.g_mobiledata_rounded),
                          label: const Text('الدخول باستخدام Google'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextButton(
                    onPressed: widget.onSignupTap,
                    child: const Text('ليس لديك حساب؟ إنشاء حساب جديد'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthLogo extends StatelessWidget {
  final String title;

  const _AuthLogo({required this.title});

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
        Text(title, style: AppTextStyles.screenSub),
      ],
    );
  }
}

class _RoleSelector extends StatelessWidget {
  final AccountRole selected;
  final ValueChanged<AccountRole> onChanged;

  const _RoleSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<AccountRole>(
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
      selected: {selected},
      onSelectionChanged: (value) => onChanged(value.first),
    );
  }
}
