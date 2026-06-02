import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/firebase_backend_service.dart';
import '../services/local_db_service.dart';
import '../services/notification_service.dart';

enum LoadStatus { initial, loading, loaded, error }

class MedicationProvider extends ChangeNotifier {
  final LocalDbService _db;
  MedicationProvider(this._db);

  LoadStatus _status = LoadStatus.initial;
  List<Medication> _medications = [];
  String? _errorMessage;

  LoadStatus get status => _status;
  List<Medication> get medications => _medications;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _status == LoadStatus.loading;
  bool get hasError => _status == LoadStatus.error;
  bool get isEmpty => _medications.isEmpty && _status == LoadStatus.loaded;

  List<Medication> get activeMedications =>
      _medications.where((m) => m.status == MedicationStatus.active).toList();

  Medication? findById(String id) {
    try {
      return _medications.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> loadMedications(String patientId) async {
    if (_status == LoadStatus.loading) return;
    _status = LoadStatus.loading;
    notifyListeners();
    try {
      final local = await _db.getMedications(patientId);
      final patientUid = FirebaseBackendService().currentUid;
      final cloud = patientUid == null
          ? const <Medication>[]
          : await FirebaseBackendService().fetchPatientMedications(patientUid);
      for (final med in cloud) {
        await _db.insertMedication(patientId, med);
      }
      final byId = <String, Medication>{
        for (final med in local) med.id: med,
        for (final med in cloud) med.id: med,
      };
      _medications = byId.values.toList();
      _status = LoadStatus.loaded;
    } catch (e) {
      _errorMessage = 'Could not load medications.';
      _status = LoadStatus.error;
    }
    notifyListeners();
  }

  // ── Patient adds a new medication ─────────────────────────────────────────
  Future<void> addMedication(
    String patientId,
    Medication med, {
    bool isArabic = true,
  }) async {
    await _db.insertMedication(patientId, med);
    await _db.logMedicationChange(
      patientId: patientId,
      medicationId: med.id,
      action: 'created',
      actorRole: 'patient',
    );
    await _handleRefillMilestone(patientId, med, isArabic: isArabic);
    _medications = [..._medications, med];
    notifyListeners();
    await _syncMedicationCloudSideEffects(
      patientId: patientId,
      medication: med,
      action: 'created',
    );
  }

  // ── Patient edits a medication ────────────────────────────────────────────
  Future<void> updateMedication(
    String patientId,
    Medication med, {
    bool isArabic = true,
  }) async {
    final previous = findById(med.id);
    await _db.updateMedication(patientId, med);
    await _db.logMedicationChange(
      patientId: patientId,
      medicationId: med.id,
      action: 'updated',
      actorRole: 'patient',
    );
    await _handleRefillMilestone(patientId, med, isArabic: isArabic);
    if (previous != null &&
        previous.needsRefill &&
        med.quantityRemaining > previous.quantityRemaining &&
        !med.needsRefill) {
      await _db.logRefillCompleted(patientId: patientId, medication: med);
      await FirebaseBackendService().logRefillCompletion(
        patientId: patientId,
        medication: med,
      );
    }
    _medications = _medications.map((m) => m.id == med.id ? med : m).toList();
    notifyListeners();
    await _syncMedicationCloudSideEffects(
      patientId: patientId,
      medication: med,
      action: 'updated',
    );
  }

  // ── Patient deletes a medication ──────────────────────────────────────────
  Future<void> deleteMedication(String medicationId) async {
    await _db.deleteMedication(medicationId);
    _medications = _medications.where((m) => m.id != medicationId).toList();
    notifyListeners();
  }

  Future<void> pauseMedication(String patientId, String medicationId) async {
    final med = findById(medicationId);
    if (med == null) return;
    final updated = med.copyWith(status: MedicationStatus.paused);
    await updateMedication(patientId, updated);
  }

  Future<void> resumeMedication(String patientId, String medicationId) async {
    final med = findById(medicationId);
    if (med == null) return;
    final updated = med.copyWith(status: MedicationStatus.active);
    await updateMedication(patientId, updated);
  }

  Future<void> _handleRefillMilestone(String patientId, Medication medication,
      {required bool isArabic}) async {
    try {
      final milestone = _refillMilestoneFor(medication);
      if (milestone == null) return;

      final alreadySent = await _db.hasRefillEventForMilestone(
        patientId: patientId,
        medicationId: medication.id,
        milestone: milestone,
      );
      if (alreadySent) return;

      await _db.logRefillEvent(
        patientId: patientId,
        medication: medication,
        milestone: milestone,
      );
      await NotificationService().showRefillAlert(
        medication: medication,
        isArabic: isArabic,
      );
      await FirebaseBackendService().logReminderEvent(
        patientId: patientId,
        medicationId: medication.id,
        eventType: 'refillReminder',
        source: 'app',
        details: {
          'milestone': milestone,
          'daysRemaining': medication.estimatedDaysRemaining,
          'quantityRemaining': medication.quantityRemaining,
        },
      );
      await FirebaseBackendService().sendRefillAlert(
        patientId: patientId,
        medication: medication,
        milestone: milestone,
      );
    } catch (e) {
      debugPrint('Refill side effects skipped: $e');
    }
  }

  int? _refillMilestoneFor(Medication medication) {
    if (medication.quantityRemaining <= 0 || medication.dosesPerDay <= 0) {
      return null;
    }
    final days = medication.estimatedDaysRemaining;
    for (final milestone in const [1, 3, 7]) {
      if (milestone <= medication.refillThreshold && days <= milestone) {
        return milestone;
      }
    }
    return null;
  }

  Future<void> _syncMedicationCloudSideEffects({
    required String patientId,
    required Medication medication,
    required String action,
  }) async {
    try {
      await FirebaseBackendService().logMedicationModification(
        patientId: patientId,
        medication: medication,
        action: action,
        actorRole: 'patient',
      );
      final patientUid = FirebaseBackendService().currentUid;
      if (patientUid != null) {
        await FirebaseBackendService().upsertPatientMedication(
          patientUid: patientUid,
          patientId: patientId,
          medication: medication,
          actorRole: 'patient',
        );
      }
    } catch (e) {
      debugPrint('Medication cloud sync skipped: $e');
      rethrow;
    }
  }
}
