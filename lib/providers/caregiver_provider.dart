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
          caregiverId: id, caregiverName: cg.name,
          medicationId: medicationId, medicationName: medicationName,
          missedAt: missedAt, sentAt: DateTime.now(),
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
}
