// Optional read-only repository contract for reports/export features.
// MED360 now runs as a standalone app: patients create their own accounts,
// enter medication schedules, confirm doses, and manage caregivers locally.

import '../models/models.dart';

abstract class MedRepository {
  Future<PatientUser> getPatient();
  Future<List<Medication>> getMedications();
  Future<List<DoseConfirmation>> getDoseHistory();
  Future<List<DoseConfirmation>> getTodaysDoses();
  Future<MonthlyAdherenceSummary> getMonthlyReport({int year, int month});
  Future<List<MonthlyAdherenceSummary>> getPastReports();
  Future<List<CaregiverNotification>> getCaregiverNotifications();
}
