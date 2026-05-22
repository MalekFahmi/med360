import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../services/firebase_backend_service.dart';
import '../services/local_db_service.dart';

enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

enum AccountRole { patient, caregiver }

class AuthProvider extends ChangeNotifier {
  final LocalDbService _db;
  final _fbAuth = fb_auth.FirebaseAuth.instance;

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
      final savedCgUid = prefs.getString('loggedInCaregiverUid');
      if (savedCgUid != null) {
        final doc = await FirebaseFirestore.instance.collection('users').doc(savedCgUid).get();
        if (doc.exists) {
          _caregiverUser = doc.data();
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
      // We use email for Firebase Auth, let's create a dummy email from phone
      final email = '$phone@med360.com';
      final cred = await _fbAuth.createUserWithEmailAndPassword(email: email, password: password);
      final uid = cred.user!.uid;

      final newPatient = PatientUser(
        id: uid,
        name: name,
        phone: phone,
        passwordHash: _hashPassword(password),
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
      await prefs.setString('loggedInPatientId', uid);

      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Sign up failed: $e';
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
      final email = '$phone@med360.com';
      final cred = await _fbAuth.signInWithEmailAndPassword(email: email, password: password);
      final uid = cred.user!.uid;

      var p = await _db.getPatientById(uid);
      if (p == null) {
        // Fallback for transition or if local db was cleared
        final doc = await FirebaseFirestore.instance.collection('patients').doc(uid).get();
        if (doc.exists) {
          p = PatientUser.fromMap({
            ...doc.data()!,
            'id': uid,
            'passwordHash': _hashPassword(password),
            'createdAt': DateTime.now().toIso8601String(), // placeholder
          });
          await _db.insertPatient(p);
        }
      }

      if (p == null) {
        _errorMessage = 'Patient data not found.';
        await _fbAuth.signOut();
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
      await prefs.setString('loggedInPatientId', uid);

      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Login failed: $e';
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  // ── Caregiver Auth ────────────────────────────────────────────────────────
  Future<bool> caregiverSignUp({
    required String name,
    required String email,
    required String password,
    required String phone,
  }) async {
    _status = AuthStatus.loading;
    notifyListeners();
    try {
      final cred = await _fbAuth.createUserWithEmailAndPassword(email: email, password: password);
      final uid = cred.user!.uid;
      final userData = {
        'uid': uid,
        'role': 'caregiver',
        'name': name,
        'email': email,
        'phone': phone,
        'createdAt': FieldValue.serverTimestamp(),
      };
      await FirebaseFirestore.instance.collection('users').doc(uid).set(userData);
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      _caregiverUser = doc.data();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('loggedInCaregiverUid', uid);
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  Future<bool> caregiverLogin({required String email, required String password}) async {
    _status = AuthStatus.loading;
    notifyListeners();
    try {
      final cred = await _fbAuth.signInWithEmailAndPassword(email: email, password: password);
      final doc = await FirebaseFirestore.instance.collection('users').doc(cred.user!.uid).get();
      if (!doc.exists || doc.data()!['role'] != 'caregiver') {
        _errorMessage = 'User not found or not a caregiver.';
        await _fbAuth.signOut();
        _status = AuthStatus.unauthenticated;
        notifyListeners();
        return false;
      }
      _caregiverUser = doc.data();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('loggedInCaregiverUid', cred.user!.uid);
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
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
