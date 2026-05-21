import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/local_db_service.dart';

enum LoadStatus { initial, loading, loaded, error }

class MedicationProvider extends ChangeNotifier {
  final LocalDbService _db;
  MedicationProvider(this._db);

  LoadStatus _status = LoadStatus.initial;
  List<Medication> _medications = [];
  String? _errorMessage;

  LoadStatus get status              => _status;
  List<Medication> get medications   => _medications;
  String? get errorMessage           => _errorMessage;
  bool get isLoading                 => _status == LoadStatus.loading;
  bool get hasError                  => _status == LoadStatus.error;
  bool get isEmpty                   => _medications.isEmpty && _status == LoadStatus.loaded;

  List<Medication> get activeMedications =>
      _medications.where((m) => m.status == MedicationStatus.active).toList();

  Medication? findById(String id) {
    try { return _medications.firstWhere((m) => m.id == id); }
    catch (_) { return null; }
  }

  Future<void> loadMedications(String patientId) async {
    if (_status == LoadStatus.loading) return;
    _status = LoadStatus.loading;
    notifyListeners();
    try {
      _medications = await _db.getMedications(patientId);
      _status = LoadStatus.loaded;
    } catch (e) {
      _errorMessage = 'Could not load medications.';
      _status = LoadStatus.error;
    }
    notifyListeners();
  }

  // ── Patient adds a new medication ─────────────────────────────────────────
  Future<void> addMedication(String patientId, Medication med) async {
    await _db.insertMedication(patientId, med);
    _medications = [..._medications, med];
    notifyListeners();
  }

  // ── Patient edits a medication ────────────────────────────────────────────
  Future<void> updateMedication(String patientId, Medication med) async {
    await _db.updateMedication(patientId, med);
    _medications = _medications.map((m) => m.id == med.id ? med : m).toList();
    notifyListeners();
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
}