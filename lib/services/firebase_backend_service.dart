import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';
import '../models/models.dart';
import 'notification_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

class FirebaseBackendService {
  static final FirebaseBackendService _instance =
      FirebaseBackendService._internal();
  factory FirebaseBackendService() => _instance;
  FirebaseBackendService._internal();

  FirebaseFirestore? _firestore;
  FirebaseAuth? _auth;
  FirebaseMessaging? _messaging;
  FirebaseStorage? _storage;
  StreamSubscription<String>? _tokenRefreshSubscription;
  bool _initialized = false;
  bool _enabled = false;
  bool _messagingEnabled = false;

  bool get isEnabled => _enabled;
  String? get currentUid => _auth?.currentUser?.uid;

  void _handleMessage(RemoteMessage message) {
    final data = message.data;
    if (data['type'] == 'missedDose') {
      NotificationService().showCaregiverAlert(
        medicationName: data['medicationName'] ?? 'medication',
        patientName: data['patientName'] ?? 'Patient',
        isArabic: data['language'] == 'ar',
      );
    } else if (data['type'] == 'caregiverAdded') {
      final isAr = data['language'] == 'ar';
      NotificationService().showCaregiverAlert(
        medicationName:
            isAr ? 'تمت إضافتك كمقدم رعاية' : 'You were added as a caregiver',
        patientName: data['patientName'] ?? 'Patient',
        isArabic: isAr,
      );
    }
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _firestore = FirebaseFirestore.instance;
      _auth = FirebaseAuth.instance;
      try {
        _storage = FirebaseStorage.instance;
      } catch (e) {
        debugPrint('Firebase Storage disabled until configured: $e');
      }
      _enabled = true;
      await testFirestoreConnectivity();
      await _initMessaging();
    } catch (e) {
      debugPrint('Firebase disabled until app config is added: $e');
      _enabled = false;
    }
  }

  Future<void> _initMessaging() async {
    try {
      _messaging = FirebaseMessaging.instance;

      await _messaging?.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // Foreground
      FirebaseMessaging.onMessage.listen(_handleMessage);

      // Background/Terminated
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);
      final initialMessage = await _messaging?.getInitialMessage();
      if (initialMessage != null) {
        _handleMessage(initialMessage);
      }

      _messagingEnabled = true;
    } catch (e) {
      debugPrint('Firebase Messaging disabled on this platform/config: $e');
      _messagingEnabled = false;
    }
  }

  Future<bool> testFirestoreConnectivity() async {
    if (!_enabled || _firestore == null) return false;
    try {
      await _firestore!
          .collection('users')
          .limit(1)
          .get(const GetOptions(source: Source.server));
      return true;
    } on FirebaseException catch (e) {
      // Permission denied still proves the app reached Firestore.
      if (e.code == 'permission-denied') return true;
      debugPrint('Firestore connectivity test failed: $e');
      return false;
    }
  }

  Future<CaregiverUser?> currentCaregiver() async {
    if (!_enabled || _auth?.currentUser == null || _firestore == null) {
      return null;
    }
    final uid = _auth!.currentUser!.uid;
    final doc = await _firestore!.collection('users').doc(uid).get();
    final data = doc.data();
    if (data == null || data['role'] != 'caregiver') return null;
    await registerCaregiverDevice();
    return CaregiverUser.fromMap(data);
  }

  Future<DoctorUser?> currentDoctor() async {
    if (!_enabled || _auth?.currentUser == null || _firestore == null) {
      return null;
    }
    final uid = _auth!.currentUser!.uid;
    final doc = await _firestore!.collection('users').doc(uid).get();
    final data = doc.data();
    if (data == null || data['role'] != 'doctor') return null;
    await registerDoctorDevice();
    return DoctorUser.fromMap({...data, 'uid': uid});
  }

  Future<PatientUser?> currentPatient({String passwordHash = ''}) async {
    if (!_enabled || _auth?.currentUser == null || _firestore == null) {
      return null;
    }
    final uid = _auth!.currentUser!.uid;
    final doc = await _firestore!.collection('users').doc(uid).get();
    final data = doc.data();
    if (data == null || data['role'] != 'patient') return null;
    final patientId = data['patientId'] as String?;
    if (patientId == null || patientId.isEmpty) return null;
    return fetchPatientByUid(uid, passwordHash: passwordHash);
  }

  Future<PatientUser?> fetchPatientByUid(
    String patientUid, {
    String passwordHash = '',
  }) async {
    if (!_enabled || _firestore == null) return null;
    final userDoc = await _firestore!.collection('users').doc(patientUid).get();
    final userData = userDoc.data();
    final patientId = userData?['patientId'] as String?;
    final patientDoc =
        await _firestore!.collection('patients').doc(patientUid).get();
    var patientData = patientDoc.data();

    if (patientData == null && patientId != null) {
      final legacyDoc =
          await _firestore!.collection('patients').doc(patientId).get();
      patientData = legacyDoc.data();
      if (patientData != null) {
        await _firestore!.collection('patients').doc(patientUid).set({
          ...patientData,
          'ownerUid': patientUid,
        }, SetOptions(merge: true));
      }
    }
    if (patientData == null) return null;

    final caregiversSnap = await _firestore!
        .collection('patients')
        .doc(patientUid)
        .collection('caregivers')
        .get();
    final caregivers = caregiversSnap.docs.map((doc) {
      final data = doc.data();
      return Caregiver(
        id: data['caregiverUid'] ?? doc.id,
        name: data['name'] ?? '',
        email: data['email'],
        phone: data['phone'] ?? '',
        relationship: data['relationship'] ?? 'Caregiver',
        permission: NotificationPermission.values.byName(
          data['permission'] ?? NotificationPermission.missedDoseOnly.name,
        ),
      );
    }).toList();

    return PatientUser(
      id: patientData['patientId'] ?? patientId ?? '',
      name: patientData['name'] ?? '',
      phone: patientData['phone'] ?? '',
      passwordHash: passwordHash,
      dateOfBirth: _dateFromAny(patientData['dateOfBirth']),
      chronicCondition: patientData['chronicCondition'],
      caregivers: caregivers,
      arabicMode: patientData['arabicMode'] ?? true,
      largeFonts: patientData['largeFonts'] ?? false,
      highContrast: patientData['highContrast'] ?? false,
      caregiverAlertsEnabled: patientData['caregiverAlertsEnabled'] ?? true,
      createdAt: _dateFromAny(patientData['createdAt']) ?? DateTime.now(),
    );
  }

  Future<PatientUser?> fetchPatientById(
    String patientId, {
    String passwordHash = '',
  }) async {
    if (!_enabled || _firestore == null) return null;
    final patientDoc =
        await _firestore!.collection('patients').doc(patientId).get();
    final patientData = patientDoc.data();
    if (patientData == null) return null;

    final caregiversSnap = await _firestore!
        .collection('patients')
        .doc(patientId)
        .collection('caregivers')
        .get();
    final caregivers = caregiversSnap.docs.map((doc) {
      final data = doc.data();
      return Caregiver(
        id: data['caregiverUid'] ?? doc.id,
        name: data['name'] ?? '',
        email: data['email'],
        phone: data['phone'] ?? '',
        relationship: data['relationship'] ?? 'Caregiver',
        permission: NotificationPermission.values.byName(
          data['permission'] ?? NotificationPermission.missedDoseOnly.name,
        ),
      );
    }).toList();

    return PatientUser(
      id: patientId,
      name: patientData['name'] ?? '',
      phone: patientData['phone'] ?? '',
      passwordHash: passwordHash,
      dateOfBirth: _dateFromAny(patientData['dateOfBirth']),
      chronicCondition: patientData['chronicCondition'],
      caregivers: caregivers,
      arabicMode: patientData['arabicMode'] ?? true,
      largeFonts: patientData['largeFonts'] ?? false,
      highContrast: patientData['highContrast'] ?? false,
      caregiverAlertsEnabled: patientData['caregiverAlertsEnabled'] ?? true,
      createdAt: _dateFromAny(patientData['createdAt']) ?? DateTime.now(),
    );
  }

  Future<void> registerPatientAuth({
    required PatientUser patient,
    required String password,
  }) async {
    if (!_enabled || _auth == null || _firestore == null) return;
    try {
      final credential = await _auth!.createUserWithEmailAndPassword(
        email: _patientEmail(patient.phone),
        password: password,
      );
      await _writePatientUserDoc(credential.user!.uid, patient);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        throw StateError(
          'This phone number is already registered. Please log in with the original password.',
        );
      }
      rethrow;
    }
  }

  Future<void> loginPatientAuth({
    required PatientUser patient,
    required String password,
  }) async {
    if (!_enabled || _auth == null || _firestore == null) return;
    try {
      final credential = await _auth!.signInWithEmailAndPassword(
        email: _patientEmail(patient.phone),
        password: password,
      );
      final userDoc =
          await _firestore!.collection('users').doc(credential.user!.uid).get();
      final userData = userDoc.data();
      if (userData == null ||
          userData['role'] != 'patient' ||
          userData['patientId'] == null) {
        await _writePatientUserDoc(credential.user!.uid, patient);
      }
    } on FirebaseAuthException {
      rethrow;
    }
  }

  Future<void> _writePatientUserDoc(String uid, PatientUser patient) async {
    debugPrint(
      '_writePatientUserDoc writing users/$uid and patients/$uid '
      '(local patientId=${patient.id})',
    );

    await _firestore!.collection('users').doc(uid).set({
      'uid': uid,
      'role': 'patient',
      'patientId': patient.id,
      'name': patient.name,
      'phone': patient.phone,
      'phoneNormalized': normalizePhone(patient.phone),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _firestore!.collection('patients').doc(uid).set({
      'uid': uid,
      'patientId': patient.id,
      'ownerUid': uid,
      'name': patient.name,
      'phone': patient.phone,
      'phoneNormalized': normalizePhone(patient.phone),
      'dateOfBirth': patient.dateOfBirth?.toIso8601String(),
      'chronicCondition': patient.chronicCondition,
      'arabicMode': patient.arabicMode,
      'largeFonts': patient.largeFonts,
      'highContrast': patient.highContrast,
      'caregiverAlertsEnabled': patient.caregiverAlertsEnabled,
      'createdAt': patient.createdAt.toIso8601String(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _mirrorPatientCaregivers(
      patientId: patient.id,
      patientUid: uid,
      caregivers: patient.caregivers,
    );
  }

  String _patientEmail(String phone) {
    final normalized = phone.replaceAll(RegExp(r'[^0-9]'), '');
    return '$normalized@patients.med360.local';
  }

  Future<CaregiverUser> registerCaregiver({
    required String name,
    required String email,
    required String password,
    required String phone,
  }) async {
    if (!_enabled || _auth == null || _firestore == null) {
      throw StateError('Firebase is not initialized.');
    }
    final credential = await _auth!.createUserWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
    final uid = credential.user!.uid;
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedPhone = normalizePhone(phone);
    await _firestore!.collection('users').doc(uid).set({
      'uid': uid,
      'role': 'caregiver',
      'name': name.trim(),
      'email': normalizedEmail,
      'phone': phone.trim(),
      'phoneNormalized': normalizedPhone,
      'createdAt': FieldValue.serverTimestamp(),
      'lastSeen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _writeCaregiverDirectory(
      uid: uid,
      name: name.trim(),
      email: normalizedEmail,
      phone: phone.trim(),
    );
    await registerCaregiverDevice();
    return CaregiverUser(
      uid: uid,
      name: name.trim(),
      email: normalizedEmail,
      phone: phone.trim(),
    );
  }

  Future<CaregiverUser> loginCaregiver({
    required String email,
    required String password,
  }) async {
    if (!_enabled || _auth == null || _firestore == null) {
      throw StateError('Firebase is not initialized.');
    }
    final credential = await _auth!.signInWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
    final uid = credential.user!.uid;
    final doc = await _firestore!.collection('users').doc(uid).get();
    final data = doc.data();
    if (data == null || data['role'] != 'caregiver') {
      await _auth!.signOut();
      throw StateError('This account is not registered as a caregiver.');
    }
    await _writeCaregiverDirectory(
      uid: uid,
      name: data['name'] ?? '',
      email: data['email'] ?? email.trim().toLowerCase(),
      phone: data['phone'] ?? '',
    );
    await registerCaregiverDevice();
    return CaregiverUser.fromMap(data);
  }

  Future<DoctorUser> registerDoctor({
    required String name,
    required String email,
    required String password,
    required String phone,
    required String specialty,
    String? licenseNumber,
  }) async {
    if (!_enabled || _auth == null || _firestore == null) {
      throw StateError('Firebase is not initialized.');
    }
    final credential = await _auth!.createUserWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
    final uid = credential.user!.uid;
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedPhone = normalizePhone(phone);
    final doctor = DoctorUser(
      uid: uid,
      name: name.trim(),
      email: normalizedEmail,
      phone: phone.trim(),
      specialty: specialty.trim(),
      licenseNumber:
          licenseNumber?.trim().isEmpty == true ? null : licenseNumber?.trim(),
    );
    await _firestore!.collection('users').doc(uid).set({
      ...doctor.toMap(),
      'role': 'doctor',
      'phoneNormalized': normalizedPhone,
      'createdAt': FieldValue.serverTimestamp(),
      'lastSeen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    try {
      await _writeDoctorDirectory(doctor);
    } catch (e) {
      debugPrint('Doctor directory write skipped after signup: $e');
    }
    await registerDoctorDevice();
    return doctor;
  }

  Future<DoctorUser> loginDoctor({
    required String email,
    required String password,
  }) async {
    if (!_enabled || _auth == null || _firestore == null) {
      throw StateError('Firebase is not initialized.');
    }
    final credential = await _auth!.signInWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
    final uid = credential.user!.uid;
    final doc = await _firestore!.collection('users').doc(uid).get();
    final data = doc.data();
    if (data == null || data['role'] != 'doctor') {
      await _auth!.signOut();
      throw StateError('This account is not registered as a doctor.');
    }
    final doctor = DoctorUser.fromMap({...data, 'uid': uid});
    try {
      await _writeDoctorDirectory(doctor);
    } catch (e) {
      debugPrint('Doctor directory refresh skipped: $e');
    }
    await registerDoctorDevice();
    return doctor;
  }

  Future<void> _writeDoctorDirectory(DoctorUser doctor) async {
    if (!_enabled || _firestore == null) return;
    await _firestore!.collection('doctorDirectory').doc(doctor.uid).set({
      ...doctor.toMap(),
      'role': 'doctor',
      'phoneNormalized': normalizePhone(doctor.phone),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _writeCaregiverDirectory({
    required String uid,
    required String name,
    required String email,
    required String phone,
  }) async {
    if (!_enabled || _firestore == null) return;
    await _firestore!.collection('caregiverDirectory').doc(uid).set({
      'uid': uid,
      'role': 'caregiver',
      'name': name,
      'email': email.trim().toLowerCase(),
      'phone': phone,
      'phoneNormalized': normalizePhone(phone),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> logoutFirebaseUser() async {
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
    await _auth?.signOut();
  }

  Future<void> registerCaregiverDevice() async {
    if (!_enabled ||
        !_messagingEnabled ||
        _firestore == null ||
        _auth == null ||
        _messaging == null) {
      return;
    }
    final caregiverUid = _auth!.currentUser?.uid;
    if (caregiverUid == null) return;
    try {
      await _messaging!.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final token = await _messaging!.getToken();
      if (token != null) {
        await _writeCaregiverToken(token);
      }
      await _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = _messaging!.onTokenRefresh.listen(
        (newToken) => _writeCaregiverToken(newToken),
      );
    } catch (e) {
      debugPrint('Caregiver FCM token registration skipped: $e');
    }
  }

  Future<void> _writeCaregiverToken(String token) async {
    final uid = _auth?.currentUser?.uid;
    if (!_enabled || _firestore == null || uid == null) return;
    await _firestore!.collection('users').doc(uid).set({
      'role': 'caregiver',
      'fcmToken': token,
      'updatedAt': FieldValue.serverTimestamp(),
      'lastSeen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await registerUserDevice(firebaseUid: uid, role: 'caregiver', token: token);
  }

  Future<void> registerDoctorDevice() async {
    if (!_enabled ||
        !_messagingEnabled ||
        _firestore == null ||
        _auth == null ||
        _messaging == null) {
      return;
    }
    final doctorUid = _auth!.currentUser?.uid;
    if (doctorUid == null) return;
    try {
      await _messaging!.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final token = await _messaging!.getToken();
      if (token != null) {
        await _writeDoctorToken(token);
      }
      await _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = _messaging!.onTokenRefresh.listen(
        (newToken) => _writeDoctorToken(newToken),
      );
    } catch (e) {
      debugPrint('Doctor FCM token registration skipped: $e');
    }
  }

  Future<void> _writeDoctorToken(String token) async {
    final uid = _auth?.currentUser?.uid;
    if (!_enabled || _firestore == null || uid == null) return;
    await _firestore!.collection('users').doc(uid).set({
      'role': 'doctor',
      'fcmToken': token,
      'updatedAt': FieldValue.serverTimestamp(),
      'lastSeen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await registerUserDevice(firebaseUid: uid, role: 'doctor', token: token);
  }

  Future<Caregiver?> findCaregiverByEmail(String email) async {
    if (!_enabled || _firestore == null) return null;
    final normalizedEmail = email.trim().toLowerCase();
    final snap = await _firestore!
        .collection('caregiverDirectory')
        .where('email', isEqualTo: normalizedEmail)
        .limit(5)
        .get();
    QueryDocumentSnapshot<Map<String, dynamic>>? doc;
    for (final candidate in snap.docs) {
      if (candidate.data()['role'] == 'caregiver') {
        doc = candidate;
        break;
      }
    }
    if (doc == null) return null;
    final data = doc.data();
    return Caregiver(
      id: data['uid'] ?? doc.id,
      name: data['name'] ?? '',
      email: data['email'],
      phone: data['phone'] ?? '',
      relationship: 'Caregiver',
      permission: NotificationPermission.missedDoseOnly,
    );
  }

  Future<Caregiver?> findCaregiverByPhone(String phone) async {
    if (!_enabled || _firestore == null) return null;
    final normalizedPhone = normalizePhone(phone);
    final snap = await _firestore!
        .collection('caregiverDirectory')
        .where('phoneNormalized', isEqualTo: normalizedPhone)
        .limit(5)
        .get();
    QueryDocumentSnapshot<Map<String, dynamic>>? doc;
    for (final candidate in snap.docs) {
      if (candidate.data()['role'] == 'caregiver') {
        doc = candidate;
        break;
      }
    }
    if (doc == null) {
      final legacySnap = await _firestore!
          .collection('caregiverDirectory')
          .where('phone', isEqualTo: phone.trim())
          .limit(5)
          .get();
      for (final candidate in legacySnap.docs) {
        if (candidate.data()['role'] == 'caregiver') {
          doc = candidate;
          break;
        }
      }
    }
    if (doc == null) return null;
    final data = doc.data();
    return Caregiver(
      id: data['uid'] ?? doc.id,
      name: data['name'] ?? '',
      email: data['email'],
      phone: data['phone'] ?? phone.trim(),
      relationship: 'Caregiver',
      permission: NotificationPermission.missedDoseOnly,
    );
  }

  Future<DoctorUser?> findDoctorByEmail(String email) async {
    if (!_enabled || _firestore == null) return null;
    final normalizedEmail = email.trim().toLowerCase();
    final snap = await _firestore!
        .collection('doctorDirectory')
        .where('email', isEqualTo: normalizedEmail)
        .limit(1)
        .get();
    if (snap.docs.isNotEmpty) {
      final doc = snap.docs.first;
      return DoctorUser.fromMap({...doc.data(), 'uid': doc.id});
    }

    final usersSnap = await _firestore!
        .collection('users')
        .where('role', isEqualTo: 'doctor')
        .where('email', isEqualTo: normalizedEmail)
        .limit(1)
        .get();
    if (usersSnap.docs.isEmpty) return null;
    final doc = usersSnap.docs.first;
    final doctor = DoctorUser.fromMap({...doc.data(), 'uid': doc.id});
    try {
      await _writeDoctorDirectory(doctor);
    } catch (e) {
      debugPrint('Doctor directory backfill skipped: $e');
    }
    return doctor;
  }

  Future<List<DoctorUser>> fetchDoctorsForCurrentPatient() async {
    final patientUid = currentUid;
    if (!_enabled || _firestore == null || patientUid == null) return const [];
    try {
      final snap = await _firestore!
          .collection('patients')
          .doc(patientUid)
          .collection('doctors')
          .get();
      return snap.docs
          .map(
            (doc) => DoctorUser(
              uid: doc.data()['doctorId'] ?? doc.id,
              name: doc.data()['name'] ?? '',
              email: doc.data()['email'] ?? '',
              phone: doc.data()['phone'] ?? '',
              specialty: doc.data()['specialty'] ?? '',
              licenseNumber: doc.data()['licenseNumber'],
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('Linked doctor load skipped: $e');
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchAssignedPatientsForDoctor(
    String doctorUid,
  ) async {
    if (!_enabled || _firestore == null) return const [];
    try {
      final relations = await _firestore!
          .collection('patientDoctorRelations')
          .where('doctorId', isEqualTo: doctorUid)
          .get();
      final patients = <Map<String, dynamic>>[];
      for (final relation in relations.docs) {
        final patientUid = relation.data()['patientUid'] as String?;
        if (patientUid == null) continue;
        try {
          final patientDoc =
              await _firestore!.collection('patients').doc(patientUid).get();
          final data = patientDoc.data() ?? {};
          patients.add({
            'patientUid': patientUid,
            'patientId': relation.data()['patientId'],
            'name': data['name'] ?? 'Patient',
            'phone': data['phone'] ?? '',
            'linkedAt': relation.data()['linkedAt'],
          });
        } catch (e) {
          debugPrint('Assigned patient detail skipped: $e');
          patients.add({
            'patientUid': patientUid,
            'patientId': relation.data()['patientId'],
            'name': 'Linked patient',
            'phone': '',
            'linkedAt': relation.data()['linkedAt'],
          });
        }
      }
      return patients;
    } catch (e) {
      debugPrint('Assigned patients load skipped: $e');
      return const [];
    }
  }

  Future<Map<String, dynamic>?> createManagedPatientForCaregiver({
    required String name,
    required String phone,
    String? chronicCondition,
  }) async {
    final caregiverUid = currentUid;
    if (!_enabled || _firestore == null || caregiverUid == null) return null;
    final patientId = 'PAT-${DateTime.now().millisecondsSinceEpoch}';
    final patientUid = 'managed_${caregiverUid}_$patientId';
    final normalizedPhone = normalizePhone(phone);

    await _firestore!.collection('patients').doc(patientUid).set({
      'uid': patientUid,
      'patientId': patientId,
      'ownerUid': caregiverUid,
      'managedByCaregiver': true,
      'name': name.trim(),
      'phone': phone.trim(),
      'phoneNormalized': normalizedPhone,
      'chronicCondition': chronicCondition,
      'arabicMode': true,
      'caregiverAlertsEnabled': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _firestore!
        .collection('patientCaregivers')
        .doc('${patientUid}_$caregiverUid')
        .set({
      'patientUid': patientUid,
      'patientId': patientId,
      'caregiverUid': caregiverUid,
      'linkedAt': FieldValue.serverTimestamp(),
      'managedByCaregiver': true,
    }, SetOptions(merge: true));

    return {
      'patientUid': patientUid,
      'patientId': patientId,
      'name': name.trim(),
      'phone': phone.trim(),
    };
  }

  Future<bool> linkExistingPatientToCurrentCaregiverByPhone(
    String phone,
  ) async {
    final caregiverUid = currentUid;
    if (!_enabled || _firestore == null || caregiverUid == null) return false;
    final normalizedPhone = normalizePhone(phone);
    final users = await _firestore!
        .collection('users')
        .where('role', isEqualTo: 'patient')
        .where('phoneNormalized', isEqualTo: normalizedPhone)
        .limit(1)
        .get();
    if (users.docs.isEmpty) return false;
    final userDoc = users.docs.first;
    final patientUid = userDoc.id;
    final patientId = userDoc.data()['patientId'] as String?;
    if (patientId == null) return false;
    await _firestore!
        .collection('patientCaregivers')
        .doc('${patientUid}_$caregiverUid')
        .set({
      'patientUid': patientUid,
      'patientId': patientId,
      'caregiverUid': caregiverUid,
      'linkedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return true;
  }

  String normalizePhone(String phone) =>
      phone.replaceAll(RegExp(r'[^0-9]'), '');

  Future<void> registerPatientDevice(PatientUser patient) async {
    final uid = currentUid;
    if (!_enabled || _firestore == null || uid == null) return;

    String? token;
    if (_messagingEnabled) {
      try {
        token = await _messaging?.getToken();
      } catch (_) {}
    }

    debugPrint(
      'registerPatientDevice writing patients/$uid '
      '(local patientId=${patient.id})',
    );

    try {
      await _firestore!.collection('patients').doc(uid).set({
        'uid': uid,
        'patientId': patient.id,
        'ownerUid': uid,
        'name': patient.name,
        'phone': patient.phone,
        'phoneNormalized': normalizePhone(patient.phone),
        'arabicMode': patient.arabicMode,
        'caregiverAlertsEnabled': patient.caregiverAlertsEnabled,
        'deviceToken': token,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await _mirrorPatientCaregivers(
        patientId: patient.id,
        patientUid: uid,
        caregivers: patient.caregivers,
      );

      if (token != null) {
        await _writePatientDeviceToken(patient, token);
        await _tokenRefreshSubscription?.cancel();
        _tokenRefreshSubscription = _messaging?.onTokenRefresh.listen(
          (newToken) => _writePatientDeviceToken(patient, newToken),
        );
      }
    } catch (e) {
      debugPrint('Patient device registration skipped: $e');
    }
  }

  Future<void> updateCurrentPatientProfile(PatientUser patient) async {
    final uid = currentUid;
    if (!_enabled || _firestore == null || uid == null) return;
    await _firestore!.collection('patients').doc(uid).set({
      'name': patient.name,
      'chronicCondition': patient.chronicCondition,
      'arabicMode': patient.arabicMode,
      'largeFonts': patient.largeFonts,
      'highContrast': patient.highContrast,
      'caregiverAlertsEnabled': patient.caregiverAlertsEnabled,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _firestore!.collection('users').doc(uid).set({
      'name': patient.name,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _writePatientDeviceToken(
    PatientUser patient,
    String token,
  ) async {
    final uid = currentUid;
    if (uid == null) return;

    await registerUserDevice(
      firebaseUid: uid,
      role: 'patient',
      token: token,
      patientId: patient.id,
    );
  }

  Future<void> registerUserDevice({
    required String firebaseUid,
    required String role,
    required String token,
    String? patientId,
  }) async {
    if (!_enabled || _firestore == null) return;

    final authUid = _auth?.currentUser?.uid;
    debugPrint('registerUserDevice passed firebaseUid=$firebaseUid');
    debugPrint('registerUserDevice authenticated uid=$authUid');

    if (authUid == null) {
      throw Exception('No authenticated Firebase user');
    }

    if (firebaseUid != authUid) {
      throw Exception('firebaseUid mismatch. Expected auth UID.');
    }

    final docPath = 'userDevices/$firebaseUid';
    debugPrint('registerUserDevice Firestore path=$docPath');

    await _firestore!.collection('userDevices').doc(firebaseUid).set({
      'firebaseUid': firebaseUid,
      'role': role,
      'fcmToken': token,
      'deviceToken': token,
      if (patientId != null) 'patientId': patientId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _mirrorPatientCaregivers({
    required String patientId,
    required String patientUid,
    required List<Caregiver> caregivers,
  }) async {
    for (final caregiver in caregivers) {
      await _firestore!
          .collection('patients')
          .doc(patientUid)
          .collection('caregivers')
          .doc(caregiver.id)
          .set({
        'caregiverUid': caregiver.id,
        'patientUid': patientUid,
        'patientId': patientId,
        'name': caregiver.name,
        'email': caregiver.email,
        'phone': caregiver.phone,
        'relationship': caregiver.relationship,
        'permission': caregiver.permission.name,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _firestore!
          .collection('patientCaregivers')
          .doc('${patientUid}_${caregiver.id}')
          .set({
        'patientUid': patientUid,
        'patientId': patientId,
        'caregiverUid': caregiver.id,
        'linkedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<void> upsertCaregiver({
    required String patientId,
    required Caregiver caregiver,
  }) async {
    final patientUid = currentUid;
    if (!_enabled || _firestore == null || patientUid == null) return;

    await _firestore!
        .collection('patients')
        .doc(patientUid)
        .collection('caregivers')
        .doc(caregiver.id)
        .set({
      'caregiverUid': caregiver.id,
      'patientUid': patientUid,
      'patientId': patientId,
      'name': caregiver.name,
      'email': caregiver.email,
      'phone': caregiver.phone,
      'relationship': caregiver.relationship,
      'permission': caregiver.permission.name,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _firestore!
        .collection('patientCaregivers')
        .doc('${patientUid}_${caregiver.id}')
        .set({
      'patientUid': patientUid,
      'patientId': patientId,
      'caregiverUid': caregiver.id,
      'linkedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> linkDoctorToCurrentPatient({
    required String patientId,
    required DoctorUser doctor,
  }) async {
    final patientUid = currentUid;
    if (!_enabled || _firestore == null || patientUid == null) return;
    if (doctor.uid.trim().isEmpty) {
      throw StateError('Doctor account is missing a Firebase UID.');
    }

    final doctorRef = _firestore!
        .collection('patients')
        .doc(patientUid)
        .collection('doctors')
        .doc(doctor.uid);
    final relationRef = _firestore!
        .collection('patientDoctorRelations')
        .doc('${patientUid}_${doctor.uid}');

    debugPrint('Linking doctor at ${doctorRef.path}');
    debugPrint('Linking doctor relation at ${relationRef.path}');

    final batch = _firestore!.batch();
    batch.set(
        doctorRef,
        {
          'doctorId': doctor.uid,
          'patientUid': patientUid,
          'patientId': patientId,
          'name': doctor.name,
          'email': doctor.email,
          'phone': doctor.phone,
          'specialty': doctor.specialty,
          'linkedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true));
    batch.set(
        relationRef,
        {
          'patientUid': patientUid,
          'patientId': patientId,
          'doctorId': doctor.uid,
          'linkedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true));
    await batch.commit();
  }

  Future<void> removeCaregiver({
    required String patientId,
    required String caregiverId,
  }) async {
    final patientUid = currentUid;
    if (!_enabled || _firestore == null || patientUid == null) return;

    await _firestore!
        .collection('patients')
        .doc(patientUid)
        .collection('caregivers')
        .doc(caregiverId)
        .delete();
    await _firestore!
        .collection('patientCaregivers')
        .doc('${patientUid}_$caregiverId')
        .delete();
  }

  Future<void> sendMissedDoseAlert({
    required String patientId,
    required String patientName,
    required String caregiverId,
    required CaregiverNotification notification,
    required bool isArabic,
  }) async {
    if (!_enabled || _firestore == null) return;
    final patientUid = await _patientUidForPatientId(patientId);
    if (patientUid == null) return;

    final payload = {
      ...notification.toMap(),
      'patientId': patientId,
      'patientUid': patientUid,
      'recipientId': caregiverId,
      'patientName': patientName,
      'title': isArabic ? 'تنبيه جرعة فائتة' : 'Missed Medication Alert',
      'body': isArabic
          ? '$patientName فات جرعة دواء مجدولة.'
          : '$patientName missed a scheduled medication.',
      'language': isArabic ? 'ar' : 'en',
      'type': 'missedDose',
      'createdAt': FieldValue.serverTimestamp(),
      'delivered': false,
    };

    final batch = _firestore!.batch();
    final patientAlertRef = _firestore!
        .collection('patients')
        .doc(patientUid)
        .collection('caregiverNotifications')
        .doc(notification.id);
    final caregiverInboxRef = _firestore!
        .collection('caregiverInboxes')
        .doc(caregiverId)
        .collection('notifications')
        .doc(notification.id);

    batch.set(patientAlertRef, payload);
    batch.set(caregiverInboxRef, payload);
    await batch.commit();
  }

  Future<void> sendRefillAlert({
    required String patientId,
    required Medication medication,
    int? milestone,
  }) async {
    if (!_enabled || _firestore == null) return;
    final patientUid = await _patientUidForPatientId(patientId);
    if (patientUid == null) return;
    final patientDoc =
        await _firestore!.collection('patients').doc(patientUid).get();
    final patientName = patientDoc.data()?['name'] ?? 'Patient';
    final notificationId =
        'REFILL-${medication.id}-${DateTime.now().millisecondsSinceEpoch}';
    final payload = {
      'id': notificationId,
      'patientId': patientId,
      'patientUid': patientUid,
      'patientName': patientName,
      'medicationId': medication.id,
      'medicationName': medication.name,
      'title': 'Refill reminder',
      'body':
          '$patientName has ${medication.estimatedDaysRemaining.toStringAsFixed(1)} days of ${medication.name} remaining.',
      'type': 'refillAlert',
      'daysRemaining': medication.estimatedDaysRemaining,
      if (milestone != null) 'milestone': milestone,
      'quantityRemaining': medication.quantityRemaining,
      'sentAt': FieldValue.serverTimestamp(),
      'acknowledged': false,
    };

    final batch = _firestore!.batch();
    final caregivers = await _firestore!
        .collection('patientCaregivers')
        .where('patientUid', isEqualTo: patientUid)
        .get();
    for (final relation in caregivers.docs) {
      final caregiverUid = relation.data()['caregiverUid'] as String?;
      if (caregiverUid == null) continue;
      batch.set(
        _firestore!
            .collection('caregiverInboxes')
            .doc(caregiverUid)
            .collection('notifications')
            .doc(notificationId),
        {...payload, 'recipientId': caregiverUid},
        SetOptions(merge: true),
      );
    }

    final doctors = await _firestore!
        .collection('patientDoctorRelations')
        .where('patientUid', isEqualTo: patientUid)
        .get();
    for (final relation in doctors.docs) {
      final doctorUid = relation.data()['doctorId'] as String?;
      if (doctorUid == null) continue;
      batch.set(
        _firestore!
            .collection('doctorInboxes')
            .doc(doctorUid)
            .collection('notifications')
            .doc(notificationId),
        {...payload, 'recipientId': doctorUid},
        SetOptions(merge: true),
      );
    }

    await batch.commit();
  }

  Future<void> logRefillCompletion({
    required String patientId,
    required Medication medication,
  }) async {
    await logReminderEvent(
      patientId: patientId,
      medicationId: medication.id,
      eventType: 'refillCompleted',
      source: 'patient',
      details: {
        'quantityRemaining': medication.quantityRemaining,
        'dosesPerDay': medication.dosesPerDay,
        'estimatedDaysRemaining': medication.estimatedDaysRemaining,
        'completedAt': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<void> upsertDose({
    required String patientId,
    required String patientName,
    required DoseConfirmation dose,
    required List<Caregiver> caregivers,
    required bool caregiverAlertsEnabled,
    required bool isArabic,
  }) async {
    if (!_enabled || _firestore == null) return;
    final patientUid = await _patientUidForPatientId(patientId);
    if (patientUid == null) return;
    await _firestore!
        .collection('patientDoses')
        .doc(_doseDocId(patientUid, dose.id))
        .set({
      ...dose.toMap(),
      'ownerUid': patientUid,
      'patientId': patientId,
      'patientName': patientName,
      'caregiverIds': caregivers.map((c) => c.id).toList(),
      'caregiverAlertsEnabled': caregiverAlertsEnabled,
      'language': isArabic ? 'ar' : 'en',
      'scheduledAt': Timestamp.fromDate(_scheduledDateTime(dose)),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateDoseStatus({
    required String patientId,
    required DoseConfirmation dose,
  }) async {
    if (!_enabled || _firestore == null) return;
    final patientUid = await _patientUidForPatientId(patientId);
    if (patientUid == null) return;
    await _firestore!
        .collection('patientDoses')
        .doc(_doseDocId(patientUid, dose.id))
        .set({
      'ownerUid': patientUid,
      'patientId': patientId,
      'status': dose.status.name,
      'confirmedAt': dose.confirmedAt?.toIso8601String(),
      'caregiverNotified': dose.caregiverNotified,
      'secondReminderSent': dose.secondReminderSent,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await logAdherenceEvent(
      patientId: patientId,
      medicationId: dose.medicationId,
      eventType: dose.status.name,
      source: 'app',
      details: {'doseId': dose.id, 'scheduledTime': dose.scheduledTime},
    );
  }

  Future<void> logAdherenceEvent({
    required String patientId,
    String? patientUid,
    String? medicationId,
    required String eventType,
    required String source,
    Map<String, dynamic>? details,
  }) async {
    if (!_enabled || _firestore == null) return;
    try {
      final resolvedPatientUid =
          patientUid ?? await _patientUidForPatientId(patientId);
      await _firestore!.collection('adherenceEvents').add({
        'patientId': patientId,
        if (resolvedPatientUid != null) 'patientUid': resolvedPatientUid,
        if (medicationId != null) 'medicationId': medicationId,
        'eventType': eventType,
        'source': source,
        'details': details ?? const {},
        'timestamp': FieldValue.serverTimestamp(),
        'actorUid': currentUid,
      });
    } catch (e) {
      debugPrint('Analytics event skipped ($eventType): $e');
    }
  }

  Future<String?> _currentUserRole() async {
    if (!_enabled || _firestore == null) return null;
    final uid = currentUid;
    if (uid == null) return null;
    final doc = await _firestore!.collection('users').doc(uid).get();
    return doc.data()?['role'] as String?;
  }

  Future<void> logReminderEvent({
    required String patientId,
    String? patientUid,
    required String medicationId,
    required String eventType,
    required String source,
    Map<String, dynamic>? details,
  }) async {
    await logAdherenceEvent(
      patientId: patientId,
      patientUid: patientUid,
      medicationId: medicationId,
      eventType: eventType,
      source: source,
      details: details,
    );
  }

  Future<void> logMedicationModification({
    required String patientId,
    String? patientUid,
    required Medication medication,
    required String action,
    required String actorRole,
  }) async {
    if (!_enabled || _firestore == null) return;
    try {
      final resolvedPatientUid =
          patientUid ?? await _patientUidForPatientId(patientId);
      if (resolvedPatientUid == null) return;
      await _firestore!.collection('medicationChangeLogs').add({
        'patientId': patientId,
        'patientUid': resolvedPatientUid,
        'medicationId': medication.id,
        'medicationName': medication.name,
        'action': action,
        'actorRole': actorRole,
        'actorUid': currentUid,
        'timestamp': FieldValue.serverTimestamp(),
        'quantityRemaining': medication.quantityRemaining,
        'dosesPerDay': medication.dosesPerDay,
        'refillThreshold': medication.refillThreshold,
      });
      final interventionEventType = switch (actorRole) {
        'caregiver' => 'caregiverMedicationIntervention',
        'doctor' => 'doctorMedicationIntervention',
        _ => null,
      };
      if (interventionEventType != null) {
        await logAdherenceEvent(
          patientId: patientId,
          patientUid: resolvedPatientUid,
          medicationId: medication.id,
          eventType: interventionEventType,
          source: actorRole,
          details: {
            'action': action,
            'medicationName': medication.name,
            'quantityRemaining': medication.quantityRemaining,
            'dosesPerDay': medication.dosesPerDay,
            'refillThreshold': medication.refillThreshold,
          },
        );
      }
    } catch (e) {
      debugPrint('Medication analytics skipped: $e');
    }
  }

  Future<void> upsertPatientMedication({
    required String patientUid,
    required String patientId,
    required Medication medication,
    required String actorRole,
  }) async {
    if (!_enabled || _firestore == null) return;
    await _firestore!
        .collection('patients')
        .doc(patientUid)
        .collection('medications')
        .doc(medication.id)
        .set({
      ...medication.toMap(),
      'patientId': patientId,
      'patientUid': patientUid,
      'actorRole': actorRole,
      'actorUid': currentUid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await logMedicationModification(
      patientId: patientId,
      patientUid: patientUid,
      medication: medication,
      action: 'upserted',
      actorRole: actorRole,
    );
  }

  Future<List<Medication>> fetchPatientMedications(String patientUid) async {
    if (!_enabled || _firestore == null) return const [];
    final snap = await _firestore!
        .collection('patients')
        .doc(patientUid)
        .collection('medications')
        .get();
    return snap.docs.map((doc) => Medication.fromMap(doc.data())).toList();
  }

  Future<void> shareReport({
    required String patientId,
    required String patientName,
    required String recipientRole,
    required String recipientId,
    required String reportType,
    required Map<String, dynamic> report,
  }) async {
    if (!_enabled || _firestore == null) return;
    final patientUid = currentUid;
    if (patientUid == null) {
      throw Exception('No authenticated Firebase user');
    }
    await _firestore!.collection('sharedReports').add({
      'patientId': patientId,
      'patientUid': patientUid,
      'patientName': patientName,
      'recipientRole': recipientRole,
      'recipientId': recipientId,
      'reportType': reportType,
      'report': report,
      'actorUid': patientUid,
      'archived': false,
      'createdAt': FieldValue.serverTimestamp(),
      'reviewedAt': null,
    });
    await logAdherenceEvent(
      patientId: patientId,
      patientUid: patientUid,
      eventType: 'reportShared',
      source: 'patient',
      details: {
        'recipientRole': recipientRole,
        'recipientId': recipientId,
        'reportType': reportType,
      },
    );
  }

  Future<void> uploadPatientReport({
    required String patientId,
    required String patientName,
    required String recipientRole,
    required String recipientId,
    required String fileName,
    required Uint8List bytes,
    String? contentType,
  }) async {
    if (!_enabled || _firestore == null || _storage == null) return;
    final patientUid = currentUid;
    if (patientUid == null) {
      throw Exception('No authenticated Firebase user');
    }

    final sanitizedName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final storagePath =
        'patientReports/$patientUid/${DateTime.now().millisecondsSinceEpoch}_$sanitizedName';
    final ref = _storage!.ref(storagePath);
    await ref.putData(
      bytes,
      SettableMetadata(
        contentType: contentType ?? _contentTypeFor(fileName),
        customMetadata: {
          'patientId': patientId,
          'patientUid': patientUid,
          'recipientRole': recipientRole,
          'recipientId': recipientId,
        },
      ),
    );
    final downloadUrl = await ref.getDownloadURL();

    await _firestore!.collection('sharedReports').add({
      'patientId': patientId,
      'patientUid': patientUid,
      'patientName': patientName,
      'recipientRole': recipientRole,
      'recipientId': recipientId,
      'reportType': 'uploaded',
      'report': {
        'label': fileName,
        'fileName': fileName,
        'storagePath': storagePath,
        'downloadUrl': downloadUrl,
        'contentType': contentType ?? _contentTypeFor(fileName),
        'sizeBytes': bytes.lengthInBytes,
      },
      'actorUid': patientUid,
      'archived': false,
      'createdAt': FieldValue.serverTimestamp(),
      'reviewedAt': null,
    });

    await logAdherenceEvent(
      patientId: patientId,
      patientUid: patientUid,
      eventType: 'patientReportUploaded',
      source: 'patient',
      details: {
        'recipientRole': recipientRole,
        'recipientId': recipientId,
        'fileName': fileName,
        'storagePath': storagePath,
        'sizeBytes': bytes.lengthInBytes,
      },
    );
  }

  Future<void> logUserEngagementEvent({
    String? patientId,
    required String eventType,
    required String source,
    Map<String, dynamic>? details,
  }) async {
    if (!_enabled || _firestore == null) return;
    try {
      final role = await _currentUserRole();
      final patientUid =
          patientId == null ? null : await _patientUidForPatientId(patientId);
      await _firestore!.collection('adherenceEvents').add({
        if (patientId != null) 'patientId': patientId,
        if (patientUid != null) 'patientUid': patientUid,
        'eventType': eventType,
        'source': source,
        'eventCategory': 'userEngagement',
        'details': {if (role != null) 'actorRole': role, ...?details},
        'timestamp': FieldValue.serverTimestamp(),
        'actorUid': currentUid,
      });
    } catch (e) {
      debugPrint('User engagement event skipped ($eventType): $e');
    }
  }

  String _contentTypeFor(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.doc')) return 'application/msword';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    return 'application/octet-stream';
  }

  Future<List<Map<String, dynamic>>> fetchSharedReportsForRecipient({
    required String recipientId,
    String? recipientRole,
  }) async {
    if (!_enabled || _firestore == null) return const [];
    Query<Map<String, dynamic>> query = _firestore!
        .collection('sharedReports')
        .where('recipientId', isEqualTo: recipientId);
    if (recipientRole != null) {
      query = query.where('recipientRole', isEqualTo: recipientRole);
    }
    final snap = await query.orderBy('createdAt', descending: true).get();
    return snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
  }

  Future<List<Map<String, dynamic>>> fetchDoctorInbox(String doctorUid) async {
    if (!_enabled || _firestore == null) return const [];
    final snap = await _firestore!
        .collection('doctorInboxes')
        .doc(doctorUid)
        .collection('notifications')
        .orderBy('sentAt', descending: true)
        .limit(20)
        .get();
    return snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
  }

  Future<void> markReportReviewed(String reportId) async {
    if (!_enabled || _firestore == null) return;
    final reportDoc =
        await _firestore!.collection('sharedReports').doc(reportId).get();
    final report = reportDoc.data();
    await _firestore!.collection('sharedReports').doc(reportId).set({
      'reviewedAt': FieldValue.serverTimestamp(),
      'archived': false,
    }, SetOptions(merge: true));
    if (report != null) {
      final role =
          await _currentUserRole() ?? report['recipientRole'] ?? 'user';
      await logAdherenceEvent(
        patientId: report['patientId'] ?? '',
        patientUid: report['patientUid'],
        eventType: role == 'doctor'
            ? 'doctorReportReviewed'
            : role == 'caregiver'
                ? 'caregiverReportReviewed'
                : 'reportReviewed',
        source: role,
        details: {'reportId': reportId, 'reportType': report['reportType']},
      );
    }
  }

  Future<void> archiveReport(String reportId) async {
    if (!_enabled || _firestore == null) return;
    final reportDoc =
        await _firestore!.collection('sharedReports').doc(reportId).get();
    final report = reportDoc.data();
    await _firestore!.collection('sharedReports').doc(reportId).set({
      'archived': true,
      'archivedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (report != null) {
      final role =
          await _currentUserRole() ?? report['recipientRole'] ?? 'user';
      await logAdherenceEvent(
        patientId: report['patientId'] ?? '',
        patientUid: report['patientUid'],
        eventType: role == 'doctor'
            ? 'doctorReportArchived'
            : role == 'caregiver'
                ? 'caregiverReportArchived'
                : 'reportArchived',
        source: role,
        details: {'reportId': reportId, 'reportType': report['reportType']},
      );
    }
  }

  String _doseDocId(String patientUid, String doseId) =>
      '${patientUid}_$doseId';

  Future<String?> _patientUidForPatientId(String patientId) async {
    final uid = currentUid;
    if (!_enabled || _firestore == null) return uid;
    if (uid != null) {
      final currentUserDoc =
          await _firestore!.collection('users').doc(uid).get();
      final currentData = currentUserDoc.data();
      if (currentData?['role'] == 'patient' &&
          currentData?['patientId'] == patientId) {
        return uid;
      }
    }

    final users = await _firestore!
        .collection('users')
        .where('role', isEqualTo: 'patient')
        .where('patientId', isEqualTo: patientId)
        .limit(1)
        .get();
    if (users.docs.isEmpty) return null;
    return users.docs.first.id;
  }

  DateTime _scheduledDateTime(DoseConfirmation dose) {
    final parts = dose.scheduledTime.split(':');
    final hour = int.tryParse(parts.first) ?? 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return DateTime(
      dose.scheduledDate.year,
      dose.scheduledDate.month,
      dose.scheduledDate.day,
      hour,
      minute,
    );
  }

  DateTime? _dateFromAny(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  Future<void> sendCaregiverAddedAlert({
    required String patientId,
    required String patientName,
    required String caregiverId,
    required bool isArabic,
  }) async {
    if (!_enabled || _firestore == null) return;
    final patientUid = await _patientUidForPatientId(patientId);
    if (patientUid == null) return;

    final notificationId = 'ADD-${DateTime.now().millisecondsSinceEpoch}';
    final payload = {
      'id': notificationId,
      'patientId': patientId,
      'patientUid': patientUid,
      'recipientId': caregiverId,
      'patientName': patientName,
      'caregiverId': caregiverId,
      'title': isArabic ? 'تمت إضافتك كمقدم رعاية' : 'Caregiver linked',
      'body': isArabic
          ? '$patientName أضافك كمقدم رعاية.'
          : '$patientName added you as a caregiver.',
      'type': 'caregiverAdded',
      'language': isArabic ? 'ar' : 'en',
      'sentAt': FieldValue.serverTimestamp(),
      'delivered': false,
    };

    await _firestore!
        .collection('caregiverInboxes')
        .doc(caregiverId)
        .collection('notifications')
        .doc(notificationId)
        .set(payload);
  }
}
