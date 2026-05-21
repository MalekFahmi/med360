// FR2 — Patient Authentication
// Clean login screen with LIMU Care branding.
// Arabic mode shows RTL layout with Arabic labels.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';
import '../../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _idCtrl   = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _idCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    // FR2: delegates to AuthProvider which calls the repository
    await context.read<AuthProvider>().login();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isAr = auth.arabicMode;

    return Scaffold(
      backgroundColor: AppColors.grayLight,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              children: [
                // ── Logo ────────────────────────────────────────────────
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.teal,
                    borderRadius: AppRadius.lg,
                  ),
                  child: const Icon(
                    Icons.medication_rounded,
                    color: AppColors.white,
                    size: 38,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'MED360',
                  style: AppTextStyles.screenTitle.copyWith(fontSize: 26),
                ),
                const SizedBox(height: 4),
                Text(
                  isAr
                      ? 'نظام متابعة الأدوية — الجامعة الليبية الدولية'
                      : 'Medication Adherence — LIMU Care',
                  style: AppTextStyles.screenSub,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xxl),

                // ── Form card ────────────────────────────────────────────
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAr ? 'تسجيل الدخول' : 'Sign in',
                        style: AppTextStyles.screenTitle.copyWith(fontSize: 18),
                      ),
                      const SizedBox(height: AppSpacing.lg),

                      // Patient ID
                      TextField(
                        controller: _idCtrl,
                        textDirection:
                            isAr ? TextDirection.rtl : TextDirection.ltr,
                        decoration: InputDecoration(
                          labelText: isAr ? 'رقم المريض' : 'Patient ID',
                          hintText: isAr ? 'مثال: 4016' : 'e.g. 4016',
                          prefixIcon: const Icon(Icons.badge_outlined),
                          border: OutlineInputBorder(
                            borderRadius: AppRadius.md,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: AppRadius.md,
                            borderSide: BorderSide(
                                color: Colors.black.withOpacity(0.12)),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // Password
                      TextField(
                        controller: _passCtrl,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          labelText: isAr ? 'كلمة المرور' : 'Password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            icon: Icon(_obscure
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: AppRadius.md,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: AppRadius.md,
                            borderSide: BorderSide(
                                color: Colors.black.withOpacity(0.12)),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),

                      // Error message
                      if (auth.errorMessage != null) ...[
                        InfoBanner(
                          message: auth.errorMessage!,
                          color: AppColors.red,
                          icon: Icons.error_outline_rounded,
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],

                      // Login button
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: auth.isLoading ? null : _login,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.teal,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: AppRadius.md),
                          ),
                          child: auth.isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.white,
                                  ),
                                )
                              : Text(
                                  isAr ? 'دخول' : 'Log in',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.lg),
                Text(
                  isAr
                      ? 'يتم إنشاء الحساب بواسطة موظف الاستقبال في نظام LIMU Care'
                      : 'Accounts are created by reception staff in LIMU Care (FR1)',
                  style: AppTextStyles.screenSub,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}