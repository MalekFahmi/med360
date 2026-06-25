import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../services/firebase_backend_domains.dart';
import '../services/firebase_backend_service.dart';
import '../services/escalation_service.dart';
import '../services/local_db_service.dart';
import '../services/notification_service.dart';

enum LoadStatus { initial, loading, loaded, error }

class MedicationProvider extends ChangeNotifier {
  static const _deletedMedicationIdsPrefix = 'deleted_medication_ids_';

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
      final deletedIds = await _deletedMedicationIds(patientId);
      for (final medicationId in deletedIds) {
        await _db.deleteMedication(medicationId, patientId: patientId);
      }
      final patientUid = FirebaseBackendService().currentUid;
      if (patientUid != null && deletedIds.isNotEmpty) {
        await _syncDeletedMedicationTombstones(
          patientId: patientId,
          patientUid: patientUid,
          medicationIds: deletedIds,
        );
      }
      final remainingDeletedIds = await _deletedMedicationIds(patientId);
      final hiddenDeletedIds = {...deletedIds, ...remainingDeletedIds};
      final local = (await _db.getMedications(patientId))
          .where((med) => !hiddenDeletedIds.contains(med.id))
          .toList();
      final cloud = patientUid == null
          ? const <Medication>[]
          : await FirebaseBackendService()
              .medications
              .fetchPatientMedications(patientUid);
      final visibleCloud =
          cloud.where((med) => !hiddenDeletedIds.contains(med.id)).toList();
      for (final med in visibleCloud) {
        await _db.insertMedication(patientId, med);
      }
      final byId = <String, Medication>{
        for (final med in local) med.id: med,
        for (final med in visibleCloud) med.id: med,
      };
      _medications = byId.values.toList();
      _status = LoadStatus.loaded;
    } catch (e) {
      _errorMessage = 'تعذر تحميل الأدوية / Could not load medications.';
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
    await _forgetDeletedMedication(patientId, med.id);
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
    await _forgetDeletedMedication(patientId, med.id);
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
      await FirebaseBackendService().medications.logRefillCompletion(
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
  Future<void> deleteMedication(String patientId, Medication medication) async {
    await _rememberDeletedMedication(patientId, medication.id);
    await _db.logMedicationChange(
      patientId: patientId,
      medicationId: medication.id,
      action: 'deleted',
      actorRole: 'patient',
    );
    await _cancelMedicationSideEffects(patientId, medication);
    await _db.deleteMedication(medication.id, patientId: patientId);
    _medications = _medications.where((m) => m.id != medication.id).toList();
    notifyListeners();
    try {
      final patientUid = FirebaseBackendService().currentUid;
      if (patientUid == null) return;
      await FirebaseBackendService().medications.deletePatientMedication(
            patientUid: patientUid,
            patientId: patientId,
            medicationId: medication.id,
            medication: medication,
            actorRole: 'patient',
          );
      await FirebaseBackendService()
          .medications
          .deletePendingDosesForMedication(
            patientId: patientId,
            medicationId: medication.id,
          );
      await _forgetDeletedMedication(patientId, medication.id);
    } catch (e) {
      debugPrint('Medication delete cloud sync skipped: $e');
    }
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
      await FirebaseBackendService().analytics.logReminderEvent(
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
      await FirebaseBackendService().notifications.sendRefillAlert(
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
    return medication.refillMilestone;
  }

  Future<void> _syncMedicationCloudSideEffects({
    required String patientId,
    required Medication medication,
    required String action,
  }) async {
    try {
      await FirebaseBackendService().medications.logMedicationModification(
            patientId: patientId,
            medication: medication,
            action: action,
            actorRole: 'patient',
          );
      final patientUid = FirebaseBackendService().currentUid;
      if (patientUid != null) {
        await FirebaseBackendService().medications.upsertPatientMedication(
              patientUid: patientUid,
              patientId: patientId,
              medication: medication,
              actorRole: 'patient',
            );
      }
    } catch (e) {
      debugPrint('Medication cloud sync skipped: $e');
    }
  }

  Future<void> _cancelMedicationSideEffects(
    String patientId,
    Medication medication,
  ) async {
    try {
      await NotificationService().cancelMedicationReminders(medication);
      final pendingDoses = await _db.getPendingDosesForMedication(
        patientId: patientId,
        medicationId: medication.id,
      );
      for (final dose in pendingDoses) {
        await NotificationService().cancelDoseEscalation(dose);
        await EscalationService().cancelDoseAutoMiss(dose);
      }
      await _db.deletePendingDosesForMedication(
        patientId: patientId,
        medicationId: medication.id,
      );
    } catch (e) {
      debugPrint('Medication delete reminder cleanup skipped: $e');
    }
  }

  Future<void> _syncDeletedMedicationTombstones({
    required String patientId,
    required String patientUid,
    required Set<String> medicationIds,
  }) async {
    final syncedIds = <String>[];
    for (final medicationId in medicationIds) {
      try {
        await FirebaseBackendService().medications.deletePatientMedication(
              patientUid: patientUid,
              patientId: patientId,
              medicationId: medicationId,
              actorRole: 'patient',
            );
        await FirebaseBackendService()
            .medications
            .deletePendingDosesForMedication(
              patientId: patientId,
              medicationId: medicationId,
            );
        syncedIds.add(medicationId);
      } catch (e) {
        debugPrint('Deferred medication delete sync skipped: $e');
      }
    }
    if (syncedIds.isNotEmpty) {
      await _forgetDeletedMedications(patientId, syncedIds);
    }
  }

  String _deletedMedicationKey(String patientId) =>
      '$_deletedMedicationIdsPrefix$patientId';

  Future<Set<String>> _deletedMedicationIds(String patientId) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_deletedMedicationKey(patientId)) ??
            const <String>[])
        .toSet();
  }

  Future<void> _rememberDeletedMedication(
    String patientId,
    String medicationId,
  ) async {
    final ids = await _deletedMedicationIds(patientId);
    if (!ids.add(medicationId)) return;
    await _saveDeletedMedicationIds(patientId, ids);
  }

  Future<void> _forgetDeletedMedication(
    String patientId,
    String medicationId,
  ) async {
    await _forgetDeletedMedications(patientId, [medicationId]);
  }

  Future<void> _forgetDeletedMedications(
    String patientId,
    Iterable<String> medicationIds,
  ) async {
    final ids = await _deletedMedicationIds(patientId);
    var changed = false;
    for (final medicationId in medicationIds) {
      changed = ids.remove(medicationId) || changed;
    }
    if (changed) {
      await _saveDeletedMedicationIds(patientId, ids);
    }
  }

  Future<void> _saveDeletedMedicationIds(
    String patientId,
    Set<String> medicationIds,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final sortedIds = medicationIds.toList()..sort();
    await prefs.setStringList(_deletedMedicationKey(patientId), sortedIds);
  }
}
