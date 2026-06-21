import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/firebase_backend_domains.dart';
import '../services/firebase_backend_service.dart';
import '../services/local_db_service.dart';
import 'adherence_provider.dart' show LoadStatus;

class CaregiverProvider extends ChangeNotifier {
  final LocalDbService _db;
  CaregiverProvider(this._db);

  List<CaregiverNotification> _notifications = [];
  List<Map<String, dynamic>> _linkedPatients = [];
  List<Map<String, dynamic>> _sharedReports = [];
  LoadStatus _status = LoadStatus.initial;
  String? _caregiverUid;
  StreamSubscription? _subscription;
  StreamSubscription? _relationshipsSubscription;

  List<CaregiverNotification> get notifications => _notifications;
  List<Map<String, dynamic>> get linkedPatients => _linkedPatients;
  List<Map<String, dynamic>> get sharedReports => _sharedReports;
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
    loadSharedReports(caregiverUid);
  }

  Future<void> loadSharedReports(String caregiverUid) async {
    try {
      _sharedReports = await FirebaseBackendService().reports.fetchForRecipient(
            recipientId: caregiverUid,
            recipientRole: 'caregiver',
          );
      notifyListeners();
    } catch (e) {
      debugPrint('Caregiver shared report load skipped: $e');
    }
  }

  Future<void> markReportReviewed(String reportId) async {
    await FirebaseBackendService().reports.markReviewed(reportId);
    if (_caregiverUid != null) await loadSharedReports(_caregiverUid!);
  }

  Future<void> archiveReport(String reportId) async {
    await FirebaseBackendService().reports.archive(reportId);
    if (_caregiverUid != null) await loadSharedReports(_caregiverUid!);
  }

  Future<bool> createManagedPatient({
    required String name,
    required String email,
    required String password,
    required String phone,
    String? chronicCondition,
  }) async {
    final created = await FirebaseBackendService()
        .careTeam
        .createManagedPatientForCaregiver(
          name: name,
          email: email,
          password: password,
          phone: phone,
          chronicCondition: chronicCondition,
        );
    if (created == null) return false;
    _linkedPatients = [created, ..._linkedPatients];
    notifyListeners();
    return true;
  }

  Future<bool> linkExistingPatientByPhone(String phone) async {
    final ok = await FirebaseBackendService()
        .careTeam
        .linkExistingPatientToCurrentCaregiverByPhone(phone);
    if (_caregiverUid != null) listenToLinkedPatients(_caregiverUid!);
    return ok;
  }

  void listenToLinkedPatients(String caregiverUid) {
    _relationshipsSubscription?.cancel();
    final firestore = FirebaseFirestore.instance;
    _relationshipsSubscription = firestore
        .collection('patientCaregivers')
        .where('caregiverUid', isEqualTo: caregiverUid)
        .snapshots()
        .listen((snapshot) async {
      try {
        final patients = <Map<String, dynamic>>[];
        for (final doc in snapshot.docs) {
          final patientId = doc.data()['patientId'] as String?;
          final idParts = doc.id.split('_');
          final patientUid = doc.data()['patientUid'] as String? ??
              (idParts.isEmpty ? null : idParts.first);
          if (patientUid == null && patientId == null) continue;
          var patientDoc = patientUid == null
              ? null
              : await firestore.collection('patients').doc(patientUid).get();
          if ((patientDoc == null || !patientDoc.exists) && patientId != null) {
            patientDoc =
                await firestore.collection('patients').doc(patientId).get();
          }
          final patientData = patientDoc?.data() ?? {};
          var adherenceRate = 0.0;
          var missedCount = 0;
          var refillRisk = 0;
          if (patientUid != null) {
            try {
              final doses = await firestore
                  .collection('patientDoses')
                  .where('ownerUid', isEqualTo: patientUid)
                  .limit(50)
                  .get();
              final resolved = doses.docs.where((dose) {
                final status = dose.data()['status'];
                return status == 'taken' || status == 'missed';
              }).toList();
              final taken = resolved
                  .where((dose) => dose.data()['status'] == 'taken')
                  .length;
              missedCount = resolved
                  .where((dose) => dose.data()['status'] == 'missed')
                  .length;
              adherenceRate = resolved.isEmpty ? 0 : taken / resolved.length;
            } catch (e) {
              debugPrint('Linked patient adherence metric skipped: $e');
            }
            try {
              final meds = await firestore
                  .collection('medicationChangeLogs')
                  .where('patientUid', isEqualTo: patientUid)
                  .limit(25)
                  .get();
              refillRisk = meds.docs
                  .where((doc) =>
                      ((doc.data()['quantityRemaining'] as num?) ?? 0) > 0 &&
                      ((doc.data()['quantityRemaining'] as num?) ?? 0) /
                              (((doc.data()['dosesPerDay'] as num?) ?? 1)) <=
                          (((doc.data()['refillThreshold'] as num?) ?? 7)))
                  .length;
            } catch (e) {
              debugPrint('Linked patient refill metric skipped: $e');
            }
          }
          patients.add({
            'patientId': patientId,
            'patientUid': patientUid,
            'name': patientData['name'] ?? patientId,
            'phone': patientData['phone'] ?? '',
            'adherenceRate': adherenceRate,
            'missedCount': missedCount,
            'refillRisk': refillRisk,
            'linkedAt': doc.data()['linkedAt'],
          });
        }
        _linkedPatients = patients;
        notifyListeners();
      } catch (e) {
        debugPrint('Linked patient stream update skipped: $e');
      }
    }, onError: (Object e) {
      debugPrint('Linked patient stream failed: $e');
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
    }, onError: (Object e) {
      debugPrint('Caregiver inbox stream failed: $e');
    });
  }

  CaregiverNotification _mapFirestoreToNotification(Map<String, dynamic> data) {
    return CaregiverNotification(
      id: data['id'] ?? '',
      caregiverId: data['caregiverId'] ?? '',
      caregiverName: data['caregiverName'] ?? '',
      patientId: data['patientId'] ?? '',
      patientUid: data['patientUid'],
      patientName: data['patientName'] ?? '',
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
    required String doseId,
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
          id: 'MISS-$doseId-$id',
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
        await FirebaseBackendService().notifications.sendMissedDoseAlert(
              patientId: patientId,
              patientName: patientName,
              caregiverId: id,
              notification: notif,
              isArabic: isArabic,
            );
        await FirebaseBackendService().analytics.logAdherenceEvent(
          patientId: patientId,
          medicationId: medicationId,
          eventType: 'caregiverNotificationSent',
          source: 'app',
          details: {
            'caregiverId': id,
            'doseId': doseId,
            'notificationId': notif.id,
            'type': notif.type,
          },
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
    final matches =
        _notifications.where((notification) => notification.id == notifId);
    final notification = matches.isEmpty ? null : matches.first;
    if (notification != null) {
      await FirebaseBackendService().analytics.logAdherenceEvent(
        patientId: notification.patientId,
        patientUid: notification.patientUid,
        medicationId: notification.medicationId,
        eventType: 'caregiverNotificationAcknowledged',
        source: 'caregiver',
        details: {
          'notificationId': notifId,
          'caregiverUid': _caregiverUid,
          'type': notification.type,
        },
      );
    }
    _notifications = _notifications
        .map((n) => n.id == notifId ? n.copyWith(acknowledged: true) : n)
        .toList();
    notifyListeners();
  }

  Future<void> markAllAsRead() async {
    if (_caregiverUid != null) {
      final batch = FirebaseFirestore.instance.batch();
      final unreadIds = _notifications
          .where((notification) => !notification.acknowledged)
          .map((notification) => notification.id);
      for (final id in unreadIds) {
        final matches =
            _notifications.where((notification) => notification.id == id);
        final notification = matches.isEmpty ? null : matches.first;
        batch.set(
          FirebaseFirestore.instance
              .collection('caregiverInboxes')
              .doc(_caregiverUid)
              .collection('notifications')
              .doc(id),
          {'acknowledged': true},
          SetOptions(merge: true),
        );
        await _db.markNotificationRead(id);
        if (notification != null) {
          await FirebaseBackendService().analytics.logAdherenceEvent(
            patientId: notification.patientId,
            patientUid: notification.patientUid,
            medicationId: notification.medicationId,
            eventType: 'caregiverNotificationAcknowledged',
            source: 'caregiver',
            details: {
              'notificationId': id,
              'caregiverUid': _caregiverUid,
              'type': notification.type,
              'bulkAction': true,
            },
          );
        }
      }
      await batch.commit();
    }
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
    await FirebaseBackendService().careTeam.sendCaregiverAddedAlert(
          patientId: patientId,
          patientName: patientName,
          caregiverId: caregiverId,
          isArabic: isArabic,
        );
  }
}
