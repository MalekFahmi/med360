import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/firebase_backend_service.dart';
import '../services/local_db_service.dart';
import 'adherence_provider.dart' show LoadStatus;

class CaregiverProvider extends ChangeNotifier {
  final LocalDbService _db;
  CaregiverProvider(this._db);

  List<CaregiverNotification> _notifications = [];
  List<Map<String, dynamic>> _linkedPatients = [];
  LoadStatus _status = LoadStatus.initial;
  String? _caregiverUid;
  StreamSubscription? _subscription;
  StreamSubscription? _relationshipsSubscription;

  List<CaregiverNotification> get notifications => _notifications;
  List<Map<String, dynamic>> get linkedPatients => _linkedPatients;
  bool get isLoading => _status == LoadStatus.loading;
  int get unreadCount => _notifications.where((n) => !n.acknowledged).length;

  Future<void> loadNotifications(String patientId) async {
    _status = LoadStatus.loading;
    notifyListeners();
    _notifications = await _db.getCaregiverNotifications(patientId);
    _status = LoadStatus.loaded;
    notifyListeners();
  }

  void listenToCaregiverData(String caregiverUid) {
    listenToInboundAlerts(caregiverUid);
    listenToLinkedPatients(caregiverUid);
  }

  void listenToLinkedPatients(String caregiverUid) {
    _relationshipsSubscription?.cancel();
    final firestore = FirebaseFirestore.instance;
    _relationshipsSubscription = firestore
        .collection('patientCaregivers')
        .where('caregiverUid', isEqualTo: caregiverUid)
        .snapshots()
        .listen((snapshot) async {
      final patients = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final patientId = doc.data()['patientId'] as String?;
        if (patientId == null) continue;
        final patientDoc =
            await firestore.collection('patients').doc(patientId).get();
        final patientData = patientDoc.data() ?? {};
        patients.add({
          'patientId': patientId,
          'name': patientData['name'] ?? patientId,
          'phone': patientData['phone'] ?? '',
          'linkedAt': doc.data()['linkedAt'],
        });
      }
      _linkedPatients = patients;
      notifyListeners();
    });
  }

  void listenToInboundAlerts(String caregiverUid) {
    _subscription?.cancel();
    _caregiverUid = caregiverUid;
    final firestore = FirebaseFirestore.instance;

    _subscription = firestore
        .collection('caregiverInboxes')
        .doc(caregiverUid)
        .collection('notifications')
        .orderBy('sentAt', descending: true)
        .snapshots()
        .listen((snapshot) {
      _notifications = snapshot.docs
          .map((doc) => _mapFirestoreToNotification(doc.data()))
          .toList();
      notifyListeners();
    });
  }

  CaregiverNotification _mapFirestoreToNotification(Map<String, dynamic> data) {
    return CaregiverNotification(
      id: data['id'] ?? '',
      caregiverId: data['caregiverId'] ?? '',
      caregiverName: data['caregiverName'] ?? data['patientName'] ?? '',
      medicationId: data['medicationId'],
      medicationName: data['medicationName'],
      missedAt:
          data['missedAt'] != null ? DateTime.parse(data['missedAt']) : null,
      sentAt: _readDate(data['sentAt']) ??
          _readDate(data['createdAt']) ??
          DateTime.now(),
      channel: NotificationChannel.inApp,
      acknowledged: data['acknowledged'] ?? false,
      type: data['type'] ?? 'missedDose',
    );
  }

  DateTime? _readDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _relationshipsSubscription?.cancel();
    super.dispose();
  }

  Future<void> dispatchMissedDoseAlert({
    required String patientId,
    required List<String> caregiverIds,
    required List<Caregiver> allCaregivers,
    required String medicationId,
    required String medicationName,
    required DateTime missedAt,
    String patientName = 'Patient',
    bool isArabic = false,
  }) async {
    for (final id in caregiverIds) {
      try {
        final cg = allCaregivers.firstWhere((c) => c.id == id);
        final notif = CaregiverNotification(
          id: 'N-${DateTime.now().millisecondsSinceEpoch}-$id',
          caregiverId: id,
          caregiverName: cg.name,
          medicationId: medicationId,
          medicationName: medicationName,
          missedAt: missedAt,
          sentAt: DateTime.now(),
          channel: NotificationChannel.both,
        );
        await _db.insertCaregiverNotification(patientId, notif);
        await FirebaseBackendService().sendMissedDoseAlert(
          patientId: patientId,
          patientName: patientName,
          caregiverId: id,
          notification: notif,
          isArabic: isArabic,
        );
        _notifications = [notif, ..._notifications];
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> markAsRead(String notifId) async {
    if (_caregiverUid != null) {
      await FirebaseFirestore.instance
          .collection('caregiverInboxes')
          .doc(_caregiverUid)
          .collection('notifications')
          .doc(notifId)
          .set({'acknowledged': true}, SetOptions(merge: true));
    }
    await _db.markNotificationRead(notifId);
    _notifications = _notifications
        .map((n) => n.id == notifId ? n.copyWith(acknowledged: true) : n)
        .toList();
    notifyListeners();
  }

  void markAllAsRead() {
    _notifications =
        _notifications.map((n) => n.copyWith(acknowledged: true)).toList();
    notifyListeners();
  }

  Future<void> dispatchCaregiverAddedAlert({
    required String patientId,
    required String patientName,
    required String caregiverId,
    required bool isArabic,
  }) async {
    await FirebaseBackendService().sendCaregiverAddedAlert(
      patientId: patientId,
      patientName: patientName,
      caregiverId: caregiverId,
      isArabic: isArabic,
    );
  }
}
