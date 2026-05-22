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

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      await Firebase.initializeApp();
      _firestore = FirebaseFirestore.instance;
      _messaging = FirebaseMessaging.instance;

      await _messaging?.requestPermission(alert: true, badge: true, sound: true);
      FirebaseMessaging.onMessage.listen((message) {
        final data = message.data;
        NotificationService().showCaregiverAlert(
          medicationName: data['medicationName'] ?? 'medication',
          patientName: data['patientName'] ?? 'Patient',
          isArabic: data['language'] == 'ar',
        );
      });

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
}
