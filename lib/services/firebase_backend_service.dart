import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'notification_service.dart';

class FirebaseBackendService {
  static final FirebaseBackendService _instance =
      FirebaseBackendService._internal();
  factory FirebaseBackendService() => _instance;
  FirebaseBackendService._internal();

  FirebaseFirestore? _firestore;
  FirebaseMessaging? _messaging;
  bool _initialized = false;
  bool _enabled = false;

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
        medicationName: isAr ? 'تمت إضافتك كمراقب' : 'You were added as a caregiver',
        patientName: data['patientName'] ?? 'Patient',
        isArabic: isAr,
      );
    }
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      await Firebase.initializeApp();
      _firestore = FirebaseFirestore.instance;
      _messaging = FirebaseMessaging.instance;

      await _messaging?.requestPermission(alert: true, badge: true, sound: true);

      // Foreground
      FirebaseMessaging.onMessage.listen(_handleMessage);

      // Background/Terminated
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);
      final initialMessage = await _messaging?.getInitialMessage();
      if (initialMessage != null) {
        _handleMessage(initialMessage);
      }

      _enabled = true;
    } catch (e) {
      debugPrint('Firebase disabled until app config is added: $e');
      _enabled = false;
    }
  }

  Future<void> registerPatientDevice(PatientUser patient) async {
    if (!_enabled || _firestore == null) return;

    String? token;
    try {
      token = await _messaging?.getToken();
    } catch (_) {}

    await _firestore!.collection('patients').doc(patient.id).set({
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
      'name': caregiver.name,
      'phone': caregiver.phone,
      'relationship': caregiver.relationship,
      'permission': caregiver.permission.name,
      'updatedAt': FieldValue.serverTimestamp(),
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
