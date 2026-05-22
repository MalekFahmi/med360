import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../services/firebase_backend_service.dart';
import '../services/local_db_service.dart';

enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

enum AccountRole { patient, caregiver }

class AuthProvider extends ChangeNotifier {
  final LocalDbService _db;

  AuthProvider(this._db);

  AuthStatus _status = AuthStatus.initial;
  PatientUser? _patient;
  CaregiverUser? _caregiver;
  AccountRole? _role;
  String? _errorMessage;

  AuthStatus get status => _status;
  PatientUser? get patient => _patient;
  CaregiverUser? get caregiver => _caregiver;
  AccountRole? get role => _role;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isLoading => _status == AuthStatus.loading;
  bool get isCaregiver => _role == AccountRole.caregiver;

  bool get arabicMode => _patient?.arabicMode ?? false;
  bool get largeFonts => _patient?.largeFonts ?? false;
  bool get highContrast => _patient?.highContrast ?? false;
  bool get caregiverAlertsEnabled => _patient?.caregiverAlertsEnabled ?? true;
  List<Caregiver> get caregivers => _patient?.caregivers ?? [];

  // ── Auto-login on app start ───────────────────────────────────────────────
  Future<void> tryAutoLogin() async {
    _status = AuthStatus.loading;
    notifyListeners();
    try {
      final caregiver = await FirebaseBackendService().currentCaregiver();
      if (caregiver != null) {
        _caregiver = caregiver;
        _role = AccountRole.caregiver;
        _status = AuthStatus.authenticated;
        notifyListeners();
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final savedId = prefs.getString('loggedInPatientId');
      if (savedId != null) {
        final p = await _db.getPatientById(savedId);
        if (p != null) {
          _patient = p;
          _role = AccountRole.patient;
          _status = AuthStatus.authenticated;
          notifyListeners();
          return;
        }
      }
    } catch (_) {}
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  // ── Sign up — patient creates their own account ───────────────────────────
  Future<bool> signUp({
    required String name,
    required String phone,
    required String password,
    DateTime? dateOfBirth,
    String? chronicCondition,
  }) async {
    _errorMessage = null;
    _status = AuthStatus.loading;
    notifyListeners();

    try {
      // Check phone not already registered
      final existing = await _db.getPatientByPhone(phone);
      if (existing != null) {
        _errorMessage = 'This phone number is already registered.';
        _status = AuthStatus.unauthenticated;
        notifyListeners();
        return false;
      }

      final newPatient = PatientUser(
        id: 'PAT-${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        phone: phone,
        passwordHash: _hashPassword(password), // simple hash for demo
        dateOfBirth: dateOfBirth,
        chronicCondition: chronicCondition,
        caregivers: [],
        createdAt: DateTime.now(),
      );

      await _db.insertPatient(newPatient);
      await FirebaseBackendService().registerPatientAuth(
        patient: newPatient,
        password: password,
      );
      await FirebaseBackendService().registerPatientDevice(newPatient);
      _patient = newPatient;
      _caregiver = null;
      _role = AccountRole.patient;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('loggedInPatientId', newPatient.id);

      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Sign up failed. Please try again.';
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  // ── Login ─────────────────────────────────────────────────────────────────
  Future<bool> login({required String phone, required String password}) async {
    _errorMessage = null;
    _status = AuthStatus.loading;
    notifyListeners();

    try {
      final p = await _db.getPatientByPhone(phone);
      if (p == null || p.passwordHash != _hashPassword(password)) {
        _errorMessage = 'Incorrect phone number or password.';
        _status = AuthStatus.unauthenticated;
        notifyListeners();
        return false;
      }

      _patient = p;
      _caregiver = null;
      _role = AccountRole.patient;
      await FirebaseBackendService().loginPatientAuth(
        patient: p,
        password: password,
      );
      await FirebaseBackendService().registerPatientDevice(p);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('loggedInPatientId', p.id);

      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Login failed. Please try again.';
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  // ── Logout ────────────────────────────────────────────────────────────────
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('loggedInPatientId');
    await FirebaseBackendService().logoutFirebaseUser();
    _patient = null;
    _caregiver = null;
    _role = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  Future<bool> registerCaregiver({
    required String name,
    required String email,
    required String password,
    required String phone,
  }) async {
    _errorMessage = null;
    _status = AuthStatus.loading;
    notifyListeners();

    try {
      _caregiver = await FirebaseBackendService().registerCaregiver(
        name: name,
        email: email,
        password: password,
        phone: phone,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('loggedInPatientId');
      _patient = null;
      _role = AccountRole.caregiver;
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  Future<bool> loginCaregiver({
    required String email,
    required String password,
  }) async {
    _errorMessage = null;
    _status = AuthStatus.loading;
    notifyListeners();

    try {
      _caregiver = await FirebaseBackendService().loginCaregiver(
        email: email,
        password: password,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('loggedInPatientId');
      _patient = null;
      _role = AccountRole.caregiver;
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  // ── Settings ──────────────────────────────────────────────────────────────
  Future<void> _saveAndNotify(PatientUser updated) async {
    _patient = updated;
    await _db.updatePatient(updated);
    notifyListeners();
  }

  Future<void> toggleArabicMode() =>
      _saveAndNotify(_patient!.copyWith(arabicMode: !arabicMode));
  Future<void> toggleLargeFonts() =>
      _saveAndNotify(_patient!.copyWith(largeFonts: !largeFonts));
  Future<void> toggleHighContrast() =>
      _saveAndNotify(_patient!.copyWith(highContrast: !highContrast));
  Future<void> toggleCaregiverAlerts() => _saveAndNotify(
      _patient!.copyWith(caregiverAlertsEnabled: !caregiverAlertsEnabled));

  Future<void> updateProfile({String? name, String? chronicCondition}) =>
      _saveAndNotify(
          _patient!.copyWith(name: name, chronicCondition: chronicCondition));

  // ── Caregiver management ──────────────────────────────────────────────────
  Future<bool> addCaregiverByEmail({
    required String email,
    required String relationship,
    NotificationPermission permission = NotificationPermission.missedDoseOnly,
  }) async {
    final registered =
        await FirebaseBackendService().findCaregiverByEmail(email);
    if (registered == null) {
      _errorMessage = 'No registered caregiver was found for that email.';
      notifyListeners();
      return false;
    }
    final cg = Caregiver(
      id: registered.id,
      name: registered.name,
      email: registered.email,
      phone: registered.phone,
      relationship: relationship,
      permission: permission,
    );
    return _tryLinkCaregiver(cg);
  }

  Future<bool> addCaregiverByPhone({
    required String phone,
    required String relationship,
    NotificationPermission permission = NotificationPermission.missedDoseOnly,
  }) async {
    final registered =
        await FirebaseBackendService().findCaregiverByPhone(phone);
    if (registered == null) {
      _errorMessage =
          'No registered caregiver account was found for that phone number.';
      notifyListeners();
      return false;
    }
    final cg = Caregiver(
      id: registered.id,
      name: registered.name,
      email: registered.email,
      phone: registered.phone,
      relationship: relationship,
      permission: permission,
    );
    return _tryLinkCaregiver(cg);
  }

  Future<bool> _tryLinkCaregiver(Caregiver caregiver) async {
    try {
      await addCaregiver(caregiver);
      return true;
    } catch (e) {
      _errorMessage = 'Could not link caregiver. Please try again.';
      notifyListeners();
      return false;
    }
  }

  Future<void> addCaregiver(Caregiver cg) async {
    await _db.insertCaregiver(_patient!.id, cg);
    await FirebaseBackendService().upsertCaregiver(
      patientId: _patient!.id,
      caregiver: cg,
    );
    await FirebaseBackendService().sendCaregiverAddedAlert(
      patientId: _patient!.id,
      patientName: _patient!.name,
      caregiverId: cg.id,
      isArabic: arabicMode,
    );
    final updated = _patient!.copyWith(caregivers: [...caregivers, cg]);
    _patient = updated;
    notifyListeners();
  }

  Future<void> removeCaregiver(String caregiverId) async {
    await _db.deleteCaregiver(caregiverId);
    await FirebaseBackendService().removeCaregiver(
      patientId: _patient!.id,
      caregiverId: caregiverId,
    );
    final updated = _patient!.copyWith(
        caregivers: caregivers.where((c) => c.id != caregiverId).toList());
    _patient = updated;
    notifyListeners();
  }

  Future<void> updateCaregiverPermission(
      String caregiverId, NotificationPermission perm) async {
    final updated = caregivers
        .map((c) => c.id == caregiverId ? c.copyWith(permission: perm) : c)
        .toList();
    await _db.insertCaregiver(
        _patient!.id, updated.firstWhere((c) => c.id == caregiverId));
    await FirebaseBackendService().upsertCaregiver(
      patientId: _patient!.id,
      caregiver: updated.firstWhere((c) => c.id == caregiverId),
    );
    _patient = _patient!.copyWith(caregivers: updated);
    notifyListeners();
  }

  // Simple deterministic hash for demo — replace with bcrypt in production
  String _hashPassword(String pw) =>
      pw.codeUnits.fold(0, (h, c) => h + c * 31).toString();
}
