import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';

import 'services/local_db_service.dart';
import 'services/notification_service.dart';
import 'services/firebase_backend_service.dart';
import 'services/escalation_service.dart';
import 'models/models.dart';
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
import 'ui/screens/doctor_dashboard_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/i18n/app_strings.dart';
import 'ui/theme/app_theme.dart';

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
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: AppColors.teal,
                primary: AppColors.teal,
                secondary: AppColors.sky,
                surface: AppColors.surface,
                surfaceContainerHighest: AppColors.surfaceMuted,
                outline: AppColors.border,
              ),
              scaffoldBackgroundColor: AppColors.pageTint,
              fontFamily: 'Roboto',
              textTheme: Theme.of(context).textTheme.apply(
                    bodyColor: AppColors.grayDark,
                    displayColor: AppColors.navy,
                  ),
              appBarTheme: const AppBarTheme(
                backgroundColor: AppColors.pageTint,
                foregroundColor: AppColors.navy,
                elevation: 0,
                scrolledUnderElevation: 0,
                centerTitle: false,
                titleTextStyle: TextStyle(
                  color: AppColors.navy,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              filledButtonTheme: FilledButtonThemeData(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.teal,
                  foregroundColor: AppColors.white,
                  minimumSize: const Size(0, 52),
                  textStyle: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                  shape: const RoundedRectangleBorder(
                    borderRadius: AppRadius.md,
                  ),
                ),
              ),
              textButtonTheme: TextButtonThemeData(
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.tealDark,
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              outlinedButtonTheme: OutlinedButtonThemeData(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.tealDark,
                  side: const BorderSide(color: AppColors.border),
                  minimumSize: const Size(0, 52),
                  textStyle: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                  shape: const RoundedRectangleBorder(
                    borderRadius: AppRadius.md,
                  ),
                ),
              ),
              inputDecorationTheme: const InputDecorationTheme(
                filled: true,
                fillColor: AppColors.surface,
                prefixIconColor: AppColors.grayMid,
                suffixIconColor: AppColors.grayMid,
                labelStyle: TextStyle(color: AppColors.grayMid),
                floatingLabelStyle: TextStyle(
                  color: AppColors.tealDark,
                  fontWeight: FontWeight.w700,
                ),
                border: OutlineInputBorder(
                  borderRadius: AppRadius.md,
                  borderSide: BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: AppRadius.md,
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: AppRadius.md,
                  borderSide: BorderSide(color: AppColors.teal, width: 1.4),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: AppRadius.md,
                  borderSide: BorderSide(color: AppColors.red),
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 16,
                ),
              ),
              navigationBarTheme: NavigationBarThemeData(
                backgroundColor: AppColors.surface,
                indicatorColor: AppColors.tealLight,
                labelTextStyle: WidgetStateProperty.all(
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                ),
                iconTheme: WidgetStateProperty.resolveWith((states) {
                  final selected = states.contains(WidgetState.selected);
                  return IconThemeData(
                    color: selected ? AppColors.tealDark : AppColors.grayMid,
                    size: selected ? 28 : 26,
                  );
                }),
              ),
              floatingActionButtonTheme: const FloatingActionButtonThemeData(
                backgroundColor: AppColors.teal,
                foregroundColor: AppColors.white,
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: AppRadius.lg),
              ),
              snackBarTheme: const SnackBarThemeData(
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: AppRadius.md),
                contentTextStyle: TextStyle(
                  color: AppColors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              bottomSheetTheme: const BottomSheetThemeData(
                backgroundColor: AppColors.surface,
                surfaceTintColor: AppColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                ),
              ),
              dividerTheme: const DividerThemeData(
                color: AppColors.border,
                thickness: 1,
                space: 1,
              ),
            ),
            locale: auth.arabicMode
                ? const Locale('ar', 'LY')
                : const Locale('en', 'US'),
            supportedLocales: const [Locale('ar', 'LY'), Locale('en', 'US')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
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
      AuthStatus.initial || AuthStatus.loading => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      AuthStatus.authenticated => auth.isDoctor
          ? const DoctorShell()
          : auth.isCaregiver
              ? const CaregiverShell()
              : const MainShell(),
      _ => const AuthScreen(),
    };
  }
}

class DoctorShell extends StatelessWidget {
  const DoctorShell({super.key});

  @override
  Widget build(BuildContext context) => const DoctorDashboardScreen();
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
        FirebaseBackendService().logUserEngagementEvent(
          eventType: 'dailyAppUsage',
          source: 'appOpen',
          details: {
            'role': 'caregiver',
            'openedAt': DateTime.now().toIso8601String(),
          },
        );
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
  AccountRole _selectedRole = AccountRole.patient;
  void _toggle() => setState(() => _showLogin = !_showLogin);
  void _setRole(AccountRole value) => setState(() => _selectedRole = value);
  @override
  Widget build(BuildContext context) {
    return _showLogin
        ? LoginScreen(
            onSignupTap: _toggle,
            selectedRole: _selectedRole,
            onRoleChanged: _setRole,
          )
        : SignupScreen(
            onLoginTap: _toggle,
            selectedRole: _selectedRole,
            onRoleChanged: _setRole,
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
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
    NotificationService().setResponseHandler(_handleNotificationAction);
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
      try {
        final pId = auth.patient!.id;
        final medicationProvider = context.read<MedicationProvider>();
        final adherenceProvider = context.read<AdherenceProvider>();
        final reportProvider = context.read<ReportProvider>();

        await FirebaseBackendService().registerPatientDevice(auth.patient!);
        await FirebaseBackendService().logUserEngagementEvent(
          patientId: pId,
          eventType: 'dailyAppUsage',
          source: 'appOpen',
          details: {
            'role': 'patient',
            'openedAt': DateTime.now().toIso8601String(),
          },
        );
        await NotificationService().requestPermissions();
        await medicationProvider.loadMedications(pId);
        final meds = medicationProvider.medications;
        for (final med in meds) {
          await NotificationService().scheduleMedicationReminders(
            med,
            patientId: pId,
            isArabic: auth.arabicMode,
          );
        }
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
      } catch (e) {
        debugPrint('Patient shell load skipped: $e');
      }
    }
  }

  Future<void> _handleNotificationAction(NotificationResponse response) async {
    if (!mounted) return;
    final payload = response.payload;
    if (payload == null || !payload.startsWith('med|')) return;

    final parts = payload.split('|');
    if (parts.length < 3) return;
    final medicationId = parts[1];
    final scheduledTime = parts[2];
    final doseId = parts.length >= 4 && parts[3].isNotEmpty ? parts[3] : null;

    final auth = context.read<AuthProvider>();
    final patient = auth.patient;
    if (patient == null) return;

    final medicationProvider = context.read<MedicationProvider>();
    final adherenceProvider = context.read<AdherenceProvider>();
    final medication = medicationProvider.findById(medicationId);
    final allPending =
        adherenceProvider.allDoses.where((dose) => dose.isPending);
    final matchingDoses = doseId == null
        ? allPending.where(
            (dose) =>
                dose.medicationId == medicationId &&
                dose.scheduledTime == scheduledTime,
          )
        : allPending.where((dose) => dose.id == doseId);
    var dose = matchingDoses.isEmpty ? null : matchingDoses.first;
    if (dose == null && medication != null) {
      dose = await adherenceProvider.ensurePendingDose(
        patientId: patient.id,
        medication: medication,
        scheduledTime: scheduledTime,
      );
    }

    final actionId = response.actionId;
    await FirebaseBackendService().logReminderEvent(
      patientId: patient.id,
      medicationId: medicationId,
      eventType: actionId == null || actionId.isEmpty
          ? 'notificationOpened'
          : 'notificationAction',
      source: 'notification',
      details: {
        'actionId': actionId ?? 'tap',
        'scheduledTime': scheduledTime,
        'payload': payload,
      },
    );

    if (actionId == null || actionId.isEmpty) return;

    if (actionId == NotificationService.actionTakeMedication) {
      if (dose == null) return;
      final didConfirm = await adherenceProvider.confirmDoseTaken(
        dose.id,
        patient.id,
        source: 'notificationAction',
      );
      if (!didConfirm) return;
      if (medication != null && medication.quantityRemaining > 0) {
        await medicationProvider.updateMedication(
          patient.id,
          medication.copyWith(
            quantityRemaining: medication.quantityRemaining - 1,
          ),
          isArabic: auth.arabicMode,
        );
      }
      return;
    }

    if (actionId == NotificationService.actionSnoozeMedication) {
      if (dose != null) {
        final snoozed = dose.copyWith(
          scheduledDate: DateTime.now(),
          scheduledTime: _formatNotificationActionTime(
            DateTime.now().add(const Duration(minutes: 5)),
          ),
        );
        await NotificationService().scheduleOneOffDoseReminder(
          dose: snoozed,
          patientId: patient.id,
          medication: medication,
          isArabic: auth.arabicMode,
          stage: 'snooze',
        );
      } else if (medication != null) {
        final time = ReminderTime.fromString(scheduledTime);
        await NotificationService().snoozeAlarm(
          med: medication,
          patientId: patient.id,
          time: time,
          isArabic: auth.arabicMode,
        );
      } else {
        return;
      }
      await FirebaseBackendService().logReminderEvent(
        patientId: patient.id,
        medicationId: medicationId,
        eventType: 'snoozedReminder',
        source: 'notification',
        details: {
          'scheduledTime': scheduledTime,
          'doseId': dose?.id,
          'snoozeMinutes': 5,
        },
      );
      return;
    }

    if (actionId == NotificationService.actionRescheduleMedication) {
      if (dose == null) return;
      final scheduledFor = DateTime.now().add(const Duration(minutes: 30));
      final updated = await adherenceProvider.rescheduleDose(
        dose.id,
        patient.id,
        scheduledFor,
        source: 'notificationAction',
        isArabic: auth.arabicMode,
      );
      if (updated == null) return;
      await NotificationService().scheduleOneOffDoseReminder(
        dose: updated,
        patientId: patient.id,
        medication: medication,
        isArabic: auth.arabicMode,
        stage: 'rescheduled',
      );
      await FirebaseBackendService().logReminderEvent(
        patientId: patient.id,
        medicationId: medicationId,
        eventType: 'rescheduledReminder',
        source: 'notification',
        details: {
          'oldScheduledTime': scheduledTime,
          'newScheduledTime': updated.scheduledTime,
          'doseId': updated.id,
          'rescheduleMinutes': 30,
        },
      );
      return;
    }
  }

  String _formatNotificationActionTime(DateTime dateTime) =>
      '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';

  void _rebuildReportsAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ReportProvider>().buildReports(
            allDoses: context.read<AdherenceProvider>().allDoses,
            medications: context.read<MedicationProvider>().medications,
          );
    });
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
    final caregiverIds = adherenceProvider.caregiverIdsForMissedDoseAlerts(
      auth.caregivers,
    );
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
    NotificationService().setResponseHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAr = context.watch<AuthProvider>().arabicMode;
    final strings = AppStrings(isAr);
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadow,
              blurRadius: 16,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: NavigationBar(
          height: 72,
          backgroundColor: AppColors.surface,
          indicatorColor: AppColors.tealLight,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          selectedIndex: _currentIndex,
          onDestinationSelected: (i) {
            setState(() => _currentIndex = i);
            if (i == 2) _rebuildReportsAfterFrame();
          },
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home_rounded),
              label: strings.home,
            ),
            NavigationDestination(
              icon: const Icon(Icons.medication_outlined),
              selectedIcon: const Icon(Icons.medication_rounded),
              label: strings.medications,
            ),
            NavigationDestination(
              icon: const Icon(Icons.bar_chart_outlined),
              selectedIcon: const Icon(Icons.bar_chart_rounded),
              label: strings.reports,
            ),
            NavigationDestination(
              icon: const Icon(Icons.people_outline),
              selectedIcon: const Icon(Icons.people_rounded),
              label: strings.care,
            ),
            NavigationDestination(
              icon: const Icon(Icons.settings_outlined),
              selectedIcon: const Icon(Icons.settings_rounded),
              label: strings.settings,
            ),
          ],
        ),
      ),
    );
  }
}
