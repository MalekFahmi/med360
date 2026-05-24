import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/local_db_service.dart';
import 'services/notification_service.dart';
import 'services/firebase_backend_service.dart';
import 'services/escalation_service.dart';
import 'providers/auth_provider.dart';
import 'providers/medication_provider.dart';
import 'providers/adherence_provider.dart';
import 'providers/report_provider.dart';
import 'providers/caregiver_provider.dart';

import 'ui/screens/login_screen.dart';
import 'ui/screens/sign_up.dart';
import 'ui/screens/dashboard_screen.dart';
import 'ui/screens/medications_screen.dart';
import 'ui/screens/adherence_screen.dart';
import 'ui/screens/caregiver_screen.dart';
import 'ui/screens/caregiver_dashboard_screen.dart';
import 'ui/screens/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService().init();
  await FirebaseBackendService().init();
  await EscalationService().initWorkmanager();
  runApp(const Med360App());
}

class Med360App extends StatelessWidget {
  const Med360App({super.key});

  @override
  Widget build(BuildContext context) {
    final LocalDbService db = LocalDbService();

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
            locale: auth.arabicMode
                ? const Locale('ar', 'LY')
                : const Locale('en', 'US'),
            builder: (context, child) {
              return Directionality(
                textDirection:
                    auth.arabicMode ? TextDirection.rtl : TextDirection.ltr,
                child: child!,
              );
            },
            home: const _AppRouter(),
          );
        },
      ),
    );
  }
}

class _AppRouter extends StatelessWidget {
  const _AppRouter();
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return switch (auth.status) {
      AuthStatus.initial ||
      AuthStatus.loading =>
        const Scaffold(body: Center(child: CircularProgressIndicator())),
      AuthStatus.authenticated =>
        auth.isCaregiver ? const CaregiverShell() : const MainShell(),
      _ => const AuthScreen(),
    };
  }
}

class CaregiverShell extends StatefulWidget {
  const CaregiverShell({super.key});

  @override
  State<CaregiverShell> createState() => _CaregiverShellState();
}

class _CaregiverShellState extends State<CaregiverShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final caregiver = context.read<AuthProvider>().caregiver;
      if (caregiver != null) {
        context.read<CaregiverProvider>().listenToCaregiverData(caregiver.uid);
      }
    });
  }

  @override
  Widget build(BuildContext context) => const CaregiverDashboardScreen();
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _showLogin = true;
  bool _caregiverMode = false;
  void _toggle() => setState(() => _showLogin = !_showLogin);
  void _setCaregiverMode(bool value) => setState(() => _caregiverMode = value);
  @override
  Widget build(BuildContext context) {
    return _showLogin
        ? LoginScreen(
            onSignupTap: _toggle,
            caregiverMode: _caregiverMode,
            onCaregiverModeChanged: _setCaregiverMode,
          )
        : SignupScreen(
            onLoginTap: _toggle,
            caregiverMode: _caregiverMode,
            onCaregiverModeChanged: _setCaregiverMode,
          );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _currentIndex = 0;
  Timer? _autoMissedTimer;
  final List<Widget> _screens = const [
    DashboardScreen(),
    MedicationsScreen(),
    AdherenceScreen(),
    CaregiverScreen(),
    SettingsScreen()
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _markOverdueDosesAndNotify();
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();

    if (auth.patient != null) {
      final pId = auth.patient!.id;
      final medicationProvider = context.read<MedicationProvider>();
      final adherenceProvider = context.read<AdherenceProvider>();
      final reportProvider = context.read<ReportProvider>();

      await FirebaseBackendService().registerPatientDevice(auth.patient!);
      await NotificationService().requestPermissions();
      await medicationProvider.loadMedications(pId);
      final meds = medicationProvider.medications;
      await adherenceProvider.loadAndGenerate(
        patientId: pId,
        medications: meds,
        patientName: auth.patient!.name,
        caregivers: auth.caregivers,
        caregiverAlertsEnabled: auth.caregiverAlertsEnabled,
        isArabic: auth.arabicMode,
      );
      await _markOverdueDosesAndNotify();
      _startAutoMissedTimer();
      if (!mounted) return;
      reportProvider.buildReports(
        allDoses: adherenceProvider.allDoses,
        medications: meds,
      );
    }
  }

  void _startAutoMissedTimer() {
    _autoMissedTimer?.cancel();
    _autoMissedTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _markOverdueDosesAndNotify(),
    );
  }

  Future<void> _markOverdueDosesAndNotify() async {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final patient = auth.patient;
    if (patient == null) return;

    final adherenceProvider = context.read<AdherenceProvider>();
    final caregiverProvider = context.read<CaregiverProvider>();
    final reportProvider = context.read<ReportProvider>();
    final medicationProvider = context.read<MedicationProvider>();

    final missedDoses = await adherenceProvider.markOverdueDosesMissed(
      patient.id,
      caregivers: auth.caregivers,
      caregiverAlertsEnabled: auth.caregiverAlertsEnabled,
    );
    if (missedDoses.isEmpty) return;

    reportProvider.buildReports(
      allDoses: adherenceProvider.allDoses,
      medications: medicationProvider.medications,
    );

    if (!auth.caregiverAlertsEnabled) return;
    final caregiverIds =
        adherenceProvider.caregiverIdsForMissedDoseAlerts(auth.caregivers);
    if (caregiverIds.isEmpty) return;

    for (final dose in missedDoses) {
      await caregiverProvider.dispatchMissedDoseAlert(
        patientId: patient.id,
        caregiverIds: caregiverIds,
        allCaregivers: auth.caregivers,
        medicationId: dose.medicationId,
        doseId: dose.id,
        medicationName: dose.medicationName,
        missedAt: DateTime.now(),
        patientName: patient.name,
        isArabic: auth.arabicMode,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoMissedTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAr = context.watch<AuthProvider>().arabicMode;
    if (_currentIndex == 2) {
      context.read<ReportProvider>().buildReports(
            allDoses: context.read<AdherenceProvider>().allDoses,
            medications: context.read<MedicationProvider>().medications,
          );
    }
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: [
          NavigationDestination(
              icon: const Icon(Icons.home), label: isAr ? 'الرئيسية' : 'Home'),
          NavigationDestination(
              icon: const Icon(Icons.medication),
              label: isAr ? 'أدويتي' : 'Meds'),
          NavigationDestination(
              icon: const Icon(Icons.bar_chart),
              label: isAr ? 'التقارير' : 'Reports'),
          NavigationDestination(
              icon: const Icon(Icons.people), label: isAr ? 'الرعاية' : 'Care'),
          NavigationDestination(
              icon: const Icon(Icons.settings),
              label: isAr ? 'إعدادات' : 'Settings'),
        ],
      ),
    );
  }
}
