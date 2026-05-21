import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/local_db_service.dart';
import 'services/notification_service.dart';
import 'providers/providers.dart';
import 'ui/theme/app_theme.dart';
import 'ui/screens/login_screen.dart';
import 'ui/screens/sign_up.dart';
import 'ui/screens/dashboard_screen.dart';
import 'ui/screens/medications_screen.dart';
import 'ui/screens/adherence_screen.dart';
import 'ui/screens/caregiver_screen.dart';
import 'ui/screens/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService().init();
  runApp(const Med360App());
}

class Med360App extends StatelessWidget {
  const Med360App({super.key});
  @override
  Widget build(BuildContext context) {
    final db = LocalDbService();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider(db)..tryAutoLogin()),
        ChangeNotifierProvider(create: (_) => MedicationProvider(db)),
        ChangeNotifierProvider(create: (_) => AdherenceProvider(db)),
        ChangeNotifierProvider(create: (_) => ReportProvider(db)),
        ChangeNotifierProvider(create: (_) => CaregiverProvider(db)),
      ],
      child: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          return MaterialApp(
            title: 'MED360',
            debugShowCheckedModeBanner: false,
            theme: _buildTheme(auth),
            locale: auth.arabicMode ? const Locale('ar', 'LY') : const Locale('en', 'US'),
            builder: (context, child) => Directionality(
              textDirection: auth.arabicMode ? TextDirection.rtl : TextDirection.ltr,
              child: child!,
            ),
            home: const _AppRouter(),
          );
        },
      ),
    );
  }
  ThemeData _buildTheme(AuthProvider auth) {
    final base = ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1D9E75)), fontFamily: auth.arabicMode ? 'Cairo' : null);
    return auth.largeFonts ? base.copyWith(textTheme: base.textTheme.apply(fontSizeFactor: 1.2)) : base;
  }
}

class _AppRouter extends StatelessWidget {
  const _AppRouter();
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return switch (auth.status) {
      AuthStatus.initial || AuthStatus.loading => const Scaffold(body: Center(child: CircularProgressIndicator())),
      AuthStatus.authenticated => const MainShell(),
      _ => const AuthScreen(),
    };
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _showLogin = true;
  @override
  Widget build(BuildContext context) => _showLogin ? LoginScreen(onSignupTap: () => setState(() => _showLogin = false)) : SignupScreen(onLoginTap: () => setState(() => _showLogin = true));
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  final _screens = const [DashboardScreen(), MedicationsScreen(), AdherenceScreen(), CaregiverScreen(), SettingsScreen()];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }
  Future<void> _loadData() async {
    final auth = context.read<AuthProvider>();
    if (auth.patient != null) {
      final pId = auth.patient!.id;
      await context.read<MedicationProvider>().loadMedications(pId);
      final meds = context.read<MedicationProvider>().medications;
      await context.read<AdherenceProvider>().loadAndGenerate(patientId: pId, medications: meds);
      if (mounted) context.read<ReportProvider>().buildReports(allDoses: context.read<AdherenceProvider>().allDoses, medications: meds);
    }
  }
  @override
  Widget build(BuildContext context) {
    final isAr = context.watch<AuthProvider>().arabicMode;
    if (_currentIndex == 2) context.read<ReportProvider>().buildReports(allDoses: context.read<AdherenceProvider>().allDoses, medications: context.read<MedicationProvider>().medications);
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home), label: isAr ? 'الرئيسية' : 'Home'),
          NavigationDestination(icon: const Icon(Icons.medication), label: isAr ? 'أدويتي' : 'Meds'),
          NavigationDestination(icon: const Icon(Icons.bar_chart), label: isAr ? 'التقارير' : 'Reports'),
          NavigationDestination(icon: const Icon(Icons.people), label: isAr ? 'الرعاية' : 'Care'),
          NavigationDestination(icon: const Icon(Icons.settings), label: isAr ? 'إعدادات' : 'Settings'),
        ],
      ),
    );
  }
}
