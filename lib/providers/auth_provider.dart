import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../services/firebase_backend_service.dart';
import '../services/local_db_service.dart';

enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

class AuthProvider extends ChangeNotifier {
  final LocalDbService _db;
  final _fbAuth = fb_auth.FirebaseAuth.instance;

  AuthProvider(this._db);

  AuthStatus _status = AuthStatus.initial;
  PatientUser? _patient;
  Map<String, dynamic>? _caregiverUser;
  String? _errorMessage;

  AuthStatus get status    => _status;
  PatientUser? get patient => _patient;
  Map<String, dynamic>? get caregiverUser => _caregiverUser;
  bool get isCaregiver => _caregiverUser != null && _caregiverUser!['role'] == 'caregiver';
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isLoading       => _status == AuthStatus.loading;

  bool get arabicMode             => _patient?.arabicMode ?? false;
  bool get largeFonts             => _patient?.largeFonts ?? false;
  bool get highContrast           => _patient?.highContrast ?? false;
  bool get caregiverAlertsEnabled => _patient?.caregiverAlertsEnabled ?? true;
  List<Caregiver> get caregivers  => _patient?.caregivers ?? [];

  // ── Auto-login on app start ───────────────────────────────────────────────
  Future<void> tryAutoLogin() async {
    _status = AuthStatus.loading;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedId = prefs.getString('loggedInPatientId');
      if (savedId != null) {
        final p = await _db.getPatientById(savedId);
        if (p != null) {
          _patient = p;
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
      await FirebaseBackendService().registerPatientDevice(newPatient);
      _patient = newPatient;

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
      _caregiverUser = userData;
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
    await prefs.remove('loggedInCaregiverUid');
    await _fbAuth.signOut();
    _patient = null;
    _caregiverUser = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  // ── Settings ──────────────────────────────────────────────────────────────
  Future<void> _saveAndNotify(PatientUser updated) async {
    _patient = updated;
    await _db.updatePatient(updated);
    notifyListeners();
  }

  Future<void> toggleArabicMode()        => _saveAndNotify(_patient!.copyWith(arabicMode: !arabicMode));
  Future<void> toggleLargeFonts()        => _saveAndNotify(_patient!.copyWith(largeFonts: !largeFonts));
  Future<void> toggleHighContrast()      => _saveAndNotify(_patient!.copyWith(highContrast: !highContrast));
  Future<void> toggleCaregiverAlerts()   => _saveAndNotify(_patient!.copyWith(caregiverAlertsEnabled: !caregiverAlertsEnabled));

  Future<void> updateProfile({String? name, String? chronicCondition}) =>
      _saveAndNotify(_patient!.copyWith(name: name, chronicCondition: chronicCondition));

  // ── Caregiver management ──────────────────────────────────────────────────
  Future<String?> addCaregiverByEmail(String email, String relationship) async {
    final cgData = await FirebaseBackendService().searchCaregiverByEmail(email);
    if (cgData == null) {
      return 'Caregiver with this email not found.';
    }

    final cg = Caregiver(
      id: cgData['uid'],
      name: cgData['name'],
      phone: cgData['phone'],
      relationship: relationship,
      permission: NotificationPermission.missedDoseOnly,
    );

    await addCaregiver(cg);
    await FirebaseBackendService().linkPatientToCaregiver(_patient!.id, cg.id);
    return null;
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
    final updated = _patient!.copyWith(
        caregivers: [...caregivers, cg]);
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
    final updated = caregivers.map((c) =>
        c.id == caregiverId ? c.copyWith(permission: perm) : c).toList();
    await _db.insertCaregiver(_patient!.id,
        updated.firstWhere((c) => c.id == caregiverId));
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
