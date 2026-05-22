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
  LoadStatus _status = LoadStatus.initial;
  StreamSubscription? _subscription;

  List<CaregiverNotification> get notifications => _notifications;
  bool get isLoading => _status == LoadStatus.loading;
  int get unreadCount => _notifications.where((n) => !n.acknowledged).length;

  Future<void> loadNotifications(String patientId) async {
    _status = LoadStatus.loading;
    notifyListeners();
    _notifications = await _db.getCaregiverNotifications(patientId);
    _status = LoadStatus.loaded;
    notifyListeners();
  }

  void clear() {
    _notifications = [];
    _subscription?.cancel();
    notifyListeners();
  }

  void listenToInboundAlerts(String uid) {
    _subscription?.cancel();
    final firestore = FirebaseFirestore.instance;

    _subscription = firestore
        .collection('caregiverInboxes')
        .doc(uid)
        .collection('notifications')
        .orderBy('sentAt', descending: true)
        .snapshots()
        .listen((snapshot) {
      bool changed = false;
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data != null) {
            final notif = _mapFirestoreToNotification(data);
            if (!_notifications.any((n) => n.id == notif.id)) {
              _notifications = [notif, ..._notifications];
              _db.insertCaregiverNotification(notif.caregiverId, notif);
              changed = true;
            }
          }
        }
      }
      if (changed) notifyListeners();
    });
  }

  CaregiverNotification _mapFirestoreToNotification(Map<String, dynamic> data) {
    return CaregiverNotification(
      id: data['id'] ?? '',
      caregiverId: data['caregiverId'] ?? '',
      caregiverName: data['caregiverName'] ?? '',
      patientId: data['patientId'] ?? '',
      patientName: data['patientName'] ?? '',
      medicationId: data['medicationId'],
      medicationName: data['medicationName'],
      missedAt: data['missedAt'] != null ? DateTime.parse(data['missedAt']) : null,
      sentAt: (data['sentAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      channel: NotificationChannel.inApp,
      acknowledged: data['acknowledged'] ?? false,
      type: data['type'] ?? 'missedDose',
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
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
          patientId: patientId,
          patientName: patientName,
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
    await _db.markNotificationRead(notifId);
    _notifications = _notifications
        .map((n) => n.id == notifId ? n.copyWith(acknowledged: true) : n)
        .toList();
    notifyListeners();
  }

  void markAllAsRead() {
    _notifications = _notifications
        .map((n) => n.copyWith(acknowledged: true))
        .toList();
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
