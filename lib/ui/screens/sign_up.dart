import 'package:flutter/material.dart';
import 'package:med360/ui/theme/app_theme.dart';
import 'package:provider/provider.dart';
import '../widgets/shared_widgets.dart';
import '../../providers/providers.dart';

class SignupScreen extends StatefulWidget {
  final VoidCallback onLoginTap;
  const SignupScreen({super.key, required this.onLoginTap});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey   = GlobalKey<FormState>();
  final _nameCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  final _condCtrl  = TextEditingController();
  bool _obscure    = true;
  bool _isCaregiverMode = false;
  DateTime? _dob;

  @override
  void dispose() {
    _nameCtrl.dispose(); _phoneCtrl.dispose(); _emailCtrl.dispose();
    _passCtrl.dispose(); _condCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    bool ok;
    if (_isCaregiverMode) {
      ok = await context.read<AuthProvider>().caregiverSignUp(
        name: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
        phone: _phoneCtrl.text.trim(),
      );
    } else {
      ok = await context.read<AuthProvider>().signUp(
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        password: _passCtrl.text,
        dateOfBirth: _dob,
        chronicCondition: _condCtrl.text.trim().isEmpty ? null : _condCtrl.text.trim(),
      );
    }
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.read<AuthProvider>().errorMessage ?? 'Sign up failed'),
        backgroundColor: AppColors.red,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.md),
        margin: const EdgeInsets.all(AppSpacing.lg),
      ));
    }
  }

  Future<void> _pickDob() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(1980),
      firstDate: DateTime(1920),
      lastDate: DateTime.now().subtract(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: AppColors.teal)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _dob = picked);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: AppColors.grayLight,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Form(
              key: _formKey,
              child: Column(children: [
                // Logo
                Container(
                  width: 68, height: 68,
                  decoration: const BoxDecoration(color: AppColors.teal, borderRadius: AppRadius.lg),
                  child: const Icon(Icons.medication_rounded, color: AppColors.white, size: 36),
                ),
                const SizedBox(height: AppSpacing.md),
                Text('MED360', style: AppTextStyles.screenTitle.copyWith(fontSize: 24)),
                const SizedBox(height: 4),
                const Text('Your personal medication reminder', style: AppTextStyles.screenSub),
                const SizedBox(height: AppSpacing.xxl),

                AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Create account', style: AppTextStyles.screenTitle.copyWith(fontSize: 18)),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.people_outline, size: 14),
                      Switch(
                        value: _isCaregiverMode,
                        onChanged: (v) => setState(() => _isCaregiverMode = v),
                        activeThumbColor: AppColors.teal,
                      ),
                    ]),
                  ]),
                  Text(_isCaregiverMode ? 'Caregiver account' : 'Patient account', style: AppTextStyles.screenSub.copyWith(fontSize: 11)),
                  const SizedBox(height: AppSpacing.lg),

                  // Name
                  TextFormField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: _inputDec('Full name', Icons.person_outline_rounded),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter your name' : null,
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Phone
                  TextFormField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: _inputDec('Phone number', Icons.phone_outlined),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Please enter your phone';
                      if (v.trim().length < 7) return 'Phone number too short';
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),

                  if (_isCaregiverMode) ...[
                    // Email
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: _inputDec('Email address', Icons.email_outlined),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter your email' : null,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],

                  // Password
                  TextFormField(
                    controller: _passCtrl,
                    obscureText: _obscure,
                    decoration: _inputDec('Password', Icons.lock_outline_rounded).copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Please enter a password';
                      if (v.length < 4) return 'Password must be at least 4 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),

                  if (!_isCaregiverMode) ...[
                  // Date of birth (optional)
                  GestureDetector(
                    onTap: _pickDob,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black.withValues(alpha: 0.2)),
                        borderRadius: AppRadius.md,
                      ),
                      child: Row(children: [
                        const Icon(Icons.cake_outlined, color: AppColors.grayMid, size: 20),
                        const SizedBox(width: 12),
                        Text(
                          _dob != null
                              ? '${_dob!.day}/${_dob!.month}/${_dob!.year}'
                              : 'Date of birth (optional)',
                          style: TextStyle(
                            fontSize: 14,
                            color: _dob != null ? AppColors.grayDark : AppColors.grayMid,
                          ),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Chronic condition (optional)
                  TextFormField(
                    controller: _condCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: _inputDec('Chronic condition (optional)', Icons.medical_information_outlined),
                  ),
                  ],
                  const SizedBox(height: AppSpacing.xl),

                  // Submit
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: auth.isLoading ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.teal,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: const RoundedRectangleBorder(borderRadius: AppRadius.md),
                      ),
                      child: auth.isLoading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white))
                          : const Text('Create account', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ])),

                const SizedBox(height: AppSpacing.lg),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('Already have an account? ', style: AppTextStyles.screenSub),
                  GestureDetector(
                    onTap: widget.onLoginTap,
                    child: const Text('Log in', style: TextStyle(fontSize: 13, color: AppColors.teal, fontWeight: FontWeight.w600)),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDec(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, size: 20),
    border: const OutlineInputBorder(borderRadius: AppRadius.md),
    enabledBorder: OutlineInputBorder(borderRadius: AppRadius.md, borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.2))),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
  );
}
