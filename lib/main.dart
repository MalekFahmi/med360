// main.dart — App entry point
// Registers all providers at the top of the widget tree so every screen
// can access them. The one-line swap comment shows exactly where to plug
// in the real API when LIMU Care endpoints are ready.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/med_repository.dart';
import 'services/static_data_service.dart';
import 'providers/auth_provider.dart';
import 'providers/medication_provider.dart';
import 'providers/adherence_provider.dart';
import 'providers/report_provider.dart';
import 'providers/caregiver_provider.dart';

// Import your UI screens and theme
import 'ui/theme/app_theme.dart';
import 'ui/screens/login_screen.dart';
import 'ui/screens/dashboard_screen.dart';
import 'ui/screens/medications_screen.dart';
import 'ui/screens/adherence_screen.dart';
import 'ui/screens/caregiver_screen.dart';
import 'ui/screens/settings_screen.dart';

//  Before:  final MedRepository repo = StaticDataService();
//  After:   final MedRepository repo = ApiService(baseUrl: 'https://limucare.ly/api');
// ──────────────────────────────────────────────────────────────────────────

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Med360App());
}

class Med360App extends StatelessWidget {
  const Med360App({super.key});

  @override
  Widget build(BuildContext context) {
    // Single repo instance shared across all providers
    final MedRepository repo = StaticDataService();

    return MultiProvider(
      providers:[
        // AuthProvider must come first — other providers may read auth state
        ChangeNotifierProvider(
          create: (_) => AuthProvider(repo)..tryAutoLogin(),
        ),

        // MedicationProvider — loads on app start
        ChangeNotifierProvider(
          create: (_) => MedicationProvider(repo),
        ),

        // AdherenceProvider — depends on medications being loaded
        ChangeNotifierProvider(
          create: (_) => AdherenceProvider(repo),
        ),

        // ReportProvider — loaded lazily when Reports screen opens
        ChangeNotifierProvider(
          create: (_) => ReportProvider(repo),
        ),

        // CaregiverProvider — loaded lazily when Caregiver screen opens
        ChangeNotifierProvider(
          create: (_) => CaregiverProvider(repo),
        ),
      ],
      child: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          return MaterialApp(
            title: 'MED360',
            debugShowCheckedModeBanner: false,

            // ── Theme ────────────────────────────────────────────────────
            theme: _buildTheme(auth),

            // ── RTL / LTR based on Arabic mode (Accessibility NFR) ───────
            locale: auth.arabicMode
                ? const Locale('ar', 'LY')
                : const Locale('en', 'US'),
            
            // We use builder to force Directionality without needing flutter_localizations package yet
            builder: (context, child) {
              return Directionality(
                textDirection: auth.arabicMode ? TextDirection.rtl : TextDirection.ltr,
                child: child!,
              );
            },

            // ── Routing ──────────────────────────────────────────────────
            home: const _AppRouter(),
          );
        },
      ),
    );
  }

  ThemeData _buildTheme(AuthProvider auth) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1D9E75), // MED360 teal
        brightness: Brightness.light,
      ),
      fontFamily: auth.arabicMode ? 'Cairo' : null, // Custom font for Arabic
    );

    // Large fonts accessibility toggle
    final textTheme = auth.largeFonts
        ? base.textTheme.apply(fontSizeFactor: 1.2)
        : base.textTheme;

    return base.copyWith(textTheme: textTheme);
  }
}

// ─── Simple router ────────────────────────────────────────────────────────
class _AppRouter extends StatelessWidget {
  const _AppRouter();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return switch (auth.status) {
      AuthStatus.initial ||
      AuthStatus.loading =>
        const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.teal))),

      AuthStatus.authenticated =>
        const MainShell(), // Opens the Bottom Nav Bar wrapper

      AuthStatus.unauthenticated ||
      AuthStatus.error =>
        const LoginScreen(), // Opens the real login screen
    };
  }
}

// ─── Main Shell (Bottom Navigation Wrapper) ───────────────────────────────

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    DashboardScreen(),
    MedicationsScreen(),
    AdherenceScreen(),
    CaregiverScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Kick off data loading as soon as the authenticated shell mounts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MedicationProvider>().loadMedications();
      context.read<AdherenceProvider>().loadHistory();
      // Caregiver & Reports can be lazy-loaded on their respective screens
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isAr = auth.arabicMode;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        backgroundColor: AppColors.white,
        indicatorColor: AppColors.tealLight,
        destinations:[
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home_rounded, color: AppColors.tealDark),
            label: isAr ? 'الرئيسية' : 'Home',
          ),
          NavigationDestination(
            icon: const Icon(Icons.medication_outlined),
            selectedIcon: const Icon(Icons.medication_rounded, color: AppColors.tealDark),
            label: isAr ? 'أدويتي' : 'Meds',
          ),
          NavigationDestination(
            icon: const Icon(Icons.bar_chart_rounded),
            selectedIcon: const Icon(Icons.bar_chart_rounded, color: AppColors.tealDark),
            label: isAr ? 'التقارير' : 'Reports',
          ),
          NavigationDestination(
            icon: const Icon(Icons.people_outline_rounded),
            selectedIcon: const Icon(Icons.people_rounded, color: AppColors.tealDark),
            label: isAr ? 'الرعاية' : 'Care',
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings_rounded, color: AppColors.tealDark),
            label: isAr ? 'إعدادات' : 'Settings',
          ),
        ],
      ),
    );
  }
}