// Abstract interface that both StaticDataService and (future) ApiService implement.
// Your providers and screens depend ONLY on this — never on the concrete class.
// When the LIMU Care API is ready:
//   1. Create ApiService that extends MedRepository
//   2. Change one line in main.dart: Provider(create: (_) => ApiService())
//   3. Everything else stays the same.

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
