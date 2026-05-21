import 'package:flutter/material.dart';
import 'package:med360/ui/theme/app_theme.dart';
import 'package:provider/provider.dart';
import '../widgets/shared_widgets.dart';
import '../../providers/providers.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback onSignupTap;
  const LoginScreen({super.key, required this.onSignupTap});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey   = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool _obscure    = true;

  @override
  void dispose() { _phoneCtrl.dispose(); _passCtrl.dispose(); super.dispose(); }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await context.read<AuthProvider>().login(
      phone: _phoneCtrl.text.trim(),
      password: _passCtrl.text,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.read<AuthProvider>().errorMessage ?? 'Login failed'),
        backgroundColor: AppColors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.md),
        margin: const EdgeInsets.all(AppSpacing.lg),
      ));
    }
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
                Container(width: 68, height: 68,
                  decoration: const BoxDecoration(color: AppColors.teal, borderRadius: AppRadius.lg),
                  child: const Icon(Icons.medication_rounded, color: AppColors.white, size: 36)),
                const SizedBox(height: AppSpacing.md),
                Text('MED360', style: AppTextStyles.screenTitle.copyWith(fontSize: 24)),
                const SizedBox(height: 4),
                const Text('Welcome back', style: AppTextStyles.screenSub),
                const SizedBox(height: AppSpacing.xxl),

                AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Sign in', style: AppTextStyles.screenTitle.copyWith(fontSize: 18)),
                  const SizedBox(height: AppSpacing.lg),

                  TextFormField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(labelText: 'Phone number', prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                      border: OutlineInputBorder(borderRadius: AppRadius.md),
                      enabledBorder: OutlineInputBorder(borderRadius: AppRadius.md, borderSide: BorderSide(color: Colors.black.withOpacity(0.2))),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14)),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your phone number' : null,
                  ),
                  const SizedBox(height: AppSpacing.md),

                  TextFormField(
                    controller: _passCtrl,
                    obscureText: _obscure,
                    decoration: InputDecoration(labelText: 'Password', prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                      suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure)),
                      border: OutlineInputBorder(borderRadius: AppRadius.md),
                      enabledBorder: OutlineInputBorder(borderRadius: AppRadius.md, borderSide: BorderSide(color: Colors.black.withOpacity(0.2))),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14)),
                    validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  SizedBox(width: double.infinity,
                    child: FilledButton(
                      onPressed: auth.isLoading ? null : _login,
                      style: FilledButton.styleFrom(backgroundColor: AppColors.teal,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: AppRadius.md)),
                      child: auth.isLoading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white))
                          : const Text('Log in', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ])),

                const SizedBox(height: AppSpacing.lg),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text("Don't have an account? ", style: AppTextStyles.screenSub),
                  GestureDetector(
                    onTap: widget.onSignupTap,
                    child: const Text('Sign up', style: TextStyle(fontSize: 13, color: AppColors.teal, fontWeight: FontWeight.w600)),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}