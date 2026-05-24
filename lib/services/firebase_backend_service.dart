import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';
import '../models/models.dart';
import 'notification_service.dart';
import '../firebase_options.dart';

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
            isAr ? 'تمت إضافتك كمراقب' : 'You were added as a caregiver',
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
          alert: true, badge: true, sound: true);
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
        await _firestore!.collection('patients').doc(patientUid).set(
            {...patientData, 'ownerUid': patientUid}, SetOptions(merge: true));
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
      arabicMode: patientData['arabicMode'] ?? false,
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
      arabicMode: patientData['arabicMode'] ?? false,
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
        await loginPatientAuth(patient: patient, password: password);
      } else {
        rethrow;
      }
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
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        await registerPatientAuth(patient: patient, password: password);
      } else {
        rethrow;
      }
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
      await _messaging!
          .requestPermission(alert: true, badge: true, sound: true);
      final token = await _messaging!.getToken();
      if (token != null) {
        await _writeCaregiverToken(token);
      }
      await _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = _messaging!.onTokenRefresh
          .listen((newToken) => _writeCaregiverToken(newToken));
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
    await registerUserDevice(
      firebaseUid: uid,
      role: 'caregiver',
      token: token,
    );
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
        patientId: patient.id, patientUid: uid, caregivers: patient.caregivers);

    if (token != null) {
      await _writePatientDeviceToken(patient, token);
      await _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = _messaging?.onTokenRefresh.listen(
        (newToken) => _writePatientDeviceToken(patient, newToken),
      );
    }
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

    final notificationId = 'ADD-${DateTime.now().millisecondsSinceEpoch}';
    final payload = {
      'id': notificationId,
      'patientId': patientId,
      if (patientUid != null) 'patientUid': patientUid,
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
