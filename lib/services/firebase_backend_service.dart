import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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
  Stream<String>? _tokenRefreshStream;
  bool _initialized = false;
  bool _enabled = false;
  bool _messagingEnabled = false;

  bool get isEnabled => _enabled;

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
      await _initMessaging();
    } catch (e) {
      debugPrint('Firebase disabled until app config is added: $e');
      _enabled = false;
    }
  }

  Future<void> _initMessaging() async {
    try {
      _messaging = FirebaseMessaging.instance;
      _tokenRefreshStream = _messaging?.onTokenRefresh;

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

  Future<CaregiverUser?> currentCaregiver() async {
    if (!_enabled || _auth?.currentUser == null || _firestore == null) {
      return null;
    }
    final uid = _auth!.currentUser!.uid;
    final doc = await _firestore!.collection('users').doc(uid).get();
    final data = doc.data();
    if (data == null || data['role'] != 'caregiver') return null;
    return CaregiverUser.fromMap(data);
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
      await _writePatientUserDoc(credential.user!.uid, patient);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        await registerPatientAuth(patient: patient, password: password);
      } else {
        rethrow;
      }
    }
  }

  Future<void> _writePatientUserDoc(String uid, PatientUser patient) async {
    await _firestore!.collection('users').doc(uid).set({
      'uid': uid,
      'role': 'patient',
      'patientId': patient.id,
      'name': patient.name,
      'phone': patient.phone,
      'phoneNormalized': normalizePhone(patient.phone),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
      email: email.trim(),
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
    await registerCaregiverDevice(uid);
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
      email: email.trim(),
      password: password,
    );
    final uid = credential.user!.uid;
    final doc = await _firestore!.collection('users').doc(uid).get();
    final data = doc.data();
    if (data == null || data['role'] != 'caregiver') {
      await _auth!.signOut();
      throw StateError('This account is not registered as a caregiver.');
    }
    await registerCaregiverDevice(uid);
    return CaregiverUser.fromMap(data);
  }

  Future<void> logoutFirebaseUser() async {
    await _auth?.signOut();
  }

  Future<void> registerCaregiverDevice(String uid) async {
    if (!_enabled ||
        !_messagingEnabled ||
        _firestore == null ||
        _messaging == null) {
      return;
    }
    try {
      await _messaging!
          .requestPermission(alert: true, badge: true, sound: true);
      final token = await _messaging!.getToken();
      if (token != null) {
        await _writeCaregiverToken(uid, token);
      }
      _tokenRefreshStream
          ?.listen((newToken) => _writeCaregiverToken(uid, newToken));
    } catch (e) {
      debugPrint('Caregiver FCM token registration skipped: $e');
    }
  }

  Future<void> _writeCaregiverToken(String uid, String token) async {
    if (!_enabled || _firestore == null) return;
    await _firestore!.collection('users').doc(uid).set({
      'role': 'caregiver',
      'fcmToken': token,
      'lastSeen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<Caregiver?> findCaregiverByEmail(String email) async {
    if (!_enabled || _firestore == null) return null;
    final snap = await _firestore!
        .collection('users')
        .where('role', isEqualTo: 'caregiver')
        .where('email', isEqualTo: email.trim().toLowerCase())
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    final data = snap.docs.first.data();
    return Caregiver(
      id: data['uid'] ?? snap.docs.first.id,
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
        .collection('users')
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
          .collection('users')
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
    if (!_enabled || _firestore == null) return;

    String? token;
    if (_messagingEnabled) {
      try {
        token = await _messaging?.getToken();
      } catch (_) {}
    }

    await _firestore!.collection('patients').doc(patient.id).set({
      'patientId': patient.id,
      'name': patient.name,
      'phone': patient.phone,
      'arabicMode': patient.arabicMode,
      'caregiverAlertsEnabled': patient.caregiverAlertsEnabled,
      'deviceToken': token,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (token != null) {
      await registerUserDevice(patient.phone, token);
    }
  }

  Future<void> registerUserDevice(String phone, String token) async {
    if (!_enabled || _firestore == null) return;

    await _firestore!.collection('userDevices').doc(phone).set({
      'deviceToken': token,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> upsertCaregiver({
    required String patientId,
    required Caregiver caregiver,
  }) async {
    if (!_enabled || _firestore == null) return;

    await _firestore!
        .collection('patients')
        .doc(patientId)
        .collection('caregivers')
        .doc(caregiver.id)
        .set({
      'caregiverUid': caregiver.id,
      'name': caregiver.name,
      'email': caregiver.email,
      'phone': caregiver.phone,
      'relationship': caregiver.relationship,
      'permission': caregiver.permission.name,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _firestore!
        .collection('patientCaregivers')
        .doc('${patientId}_${caregiver.id}')
        .set({
      'patientId': patientId,
      'caregiverUid': caregiver.id,
      'linkedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> removeCaregiver({
    required String patientId,
    required String caregiverId,
  }) async {
    if (!_enabled || _firestore == null) return;

    await _firestore!
        .collection('patients')
        .doc(patientId)
        .collection('caregivers')
        .doc(caregiverId)
        .delete();
    await _firestore!
        .collection('patientCaregivers')
        .doc('${patientId}_$caregiverId')
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

    final payload = {
      ...notification.toMap(),
      'patientId': patientId,
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
        .doc(patientId)
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

  Future<void> sendCaregiverAddedAlert({
    required String patientId,
    required String patientName,
    required String caregiverId,
    required bool isArabic,
  }) async {
    if (!_enabled || _firestore == null) return;

    final notificationId = 'ADD-${DateTime.now().millisecondsSinceEpoch}';
    final payload = {
      'id': notificationId,
      'patientId': patientId,
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
