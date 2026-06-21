import 'dart:typed_data';

import '../models/models.dart';
import 'firebase_backend_service.dart';

extension FirebaseBackendDomains on FirebaseBackendService {
  FirebaseAccountDomain get accounts => FirebaseAccountDomain(this);
  FirebaseCareTeamDomain get careTeam => FirebaseCareTeamDomain(this);
  FirebaseMedicationDomain get medications => FirebaseMedicationDomain(this);
  FirebaseReportDomain get reports => FirebaseReportDomain(this);
  FirebaseNotificationDomain get notifications =>
      FirebaseNotificationDomain(this);
  FirebaseAnalyticsDomain get analytics => FirebaseAnalyticsDomain(this);
}

class FirebaseAccountDomain {
  final FirebaseBackendService _backend;

  const FirebaseAccountDomain(this._backend);

  Future<PatientUser?> currentPatient({String passwordHash = ''}) =>
      _backend.currentPatient(passwordHash: passwordHash);
  Future<CaregiverUser?> currentCaregiver() => _backend.currentCaregiver();
  Future<DoctorUser?> currentDoctor() => _backend.currentDoctor();
  Future<void> logout() => _backend.logoutFirebaseUser();
  Future<void> registerPatientAuth({
    required PatientUser patient,
    required String password,
  }) =>
      _backend.registerPatientAuth(patient: patient, password: password);
  Future<void> loginPatientAuth({
    required PatientUser patient,
    required String password,
  }) =>
      _backend.loginPatientAuth(patient: patient, password: password);
}

class FirebaseCareTeamDomain {
  final FirebaseBackendService _backend;

  const FirebaseCareTeamDomain(this._backend);

  Future<List<DoctorUser>> fetchDoctorsForCurrentPatient() =>
      _backend.fetchDoctorsForCurrentPatient();
  Future<List<Map<String, dynamic>>> fetchAssignedPatientsForDoctor(
    String doctorUid,
  ) =>
      _backend.fetchAssignedPatientsForDoctor(doctorUid);
  Future<bool> linkPatientToCurrentDoctorByPhone(String phone) =>
      _backend.linkPatientToCurrentDoctorByPhone(phone);
  Future<bool> linkExistingPatientToCurrentCaregiverByPhone(String phone) =>
      _backend.linkExistingPatientToCurrentCaregiverByPhone(phone);
  Future<Map<String, dynamic>?> createManagedPatientForCaregiver({
    required String name,
    required String email,
    required String password,
    required String phone,
    String? chronicCondition,
  }) =>
      _backend.createManagedPatientForCaregiver(
        name: name,
        email: email,
        password: password,
        phone: phone,
        chronicCondition: chronicCondition,
      );
  Future<void> sendCaregiverAddedAlert({
    required String patientId,
    required String patientName,
    required String caregiverId,
    required bool isArabic,
  }) =>
      _backend.sendCaregiverAddedAlert(
        patientId: patientId,
        patientName: patientName,
        caregiverId: caregiverId,
        isArabic: isArabic,
      );
}

class FirebaseMedicationDomain {
  final FirebaseBackendService _backend;

  const FirebaseMedicationDomain(this._backend);

  Future<void> upsertPatientMedication({
    required String patientUid,
    required String patientId,
    required Medication medication,
    required String actorRole,
  }) =>
      _backend.upsertPatientMedication(
        patientUid: patientUid,
        patientId: patientId,
        medication: medication,
        actorRole: actorRole,
      );
  Future<List<Medication>> fetchPatientMedications(String patientUid) =>
      _backend.fetchPatientMedications(patientUid);
  Future<void> logMedicationModification({
    required String patientId,
    String? patientUid,
    required Medication medication,
    required String action,
    required String actorRole,
  }) =>
      _backend.logMedicationModification(
        patientId: patientId,
        patientUid: patientUid,
        medication: medication,
        action: action,
        actorRole: actorRole,
      );
  Future<void> logRefillCompletion({
    required String patientId,
    required Medication medication,
  }) =>
      _backend.logRefillCompletion(
        patientId: patientId,
        medication: medication,
      );
}

class FirebaseReportDomain {
  final FirebaseBackendService _backend;

  const FirebaseReportDomain(this._backend);

  Future<void> share({
    required String patientId,
    required String patientName,
    required String recipientRole,
    required String recipientId,
    required String reportType,
    required Map<String, dynamic> report,
  }) =>
      _backend.shareReport(
        patientId: patientId,
        patientName: patientName,
        recipientRole: recipientRole,
        recipientId: recipientId,
        reportType: reportType,
        report: report,
      );
  Future<void> upload({
    required String patientId,
    required String patientName,
    required String recipientRole,
    required String recipientId,
    required String fileName,
    required Uint8List bytes,
    String? contentType,
  }) =>
      _backend.uploadPatientReport(
        patientId: patientId,
        patientName: patientName,
        recipientRole: recipientRole,
        recipientId: recipientId,
        fileName: fileName,
        bytes: bytes,
        contentType: contentType,
      );
  Future<List<Map<String, dynamic>>> fetchForRecipient({
    required String recipientId,
    String? recipientRole,
  }) =>
      _backend.fetchSharedReportsForRecipient(
        recipientId: recipientId,
        recipientRole: recipientRole,
      );
  Future<void> markReviewed(String reportId) =>
      _backend.markReportReviewed(reportId);
  Future<void> archive(String reportId) => _backend.archiveReport(reportId);
}

class FirebaseNotificationDomain {
  final FirebaseBackendService _backend;

  const FirebaseNotificationDomain(this._backend);

  Future<void> sendMissedDoseAlert({
    required String patientId,
    required String patientName,
    required String caregiverId,
    required CaregiverNotification notification,
    required bool isArabic,
  }) =>
      _backend.sendMissedDoseAlert(
        patientId: patientId,
        patientName: patientName,
        caregiverId: caregiverId,
        notification: notification,
        isArabic: isArabic,
      );
  Future<void> sendRefillAlert({
    required String patientId,
    required Medication medication,
    int? milestone,
  }) =>
      _backend.sendRefillAlert(
        patientId: patientId,
        medication: medication,
        milestone: milestone,
      );
}

class FirebaseAnalyticsDomain {
  final FirebaseBackendService _backend;

  const FirebaseAnalyticsDomain(this._backend);

  Future<void> logAdherenceEvent({
    required String patientId,
    String? patientUid,
    String? medicationId,
    required String eventType,
    required String source,
    Map<String, dynamic>? details,
  }) =>
      _backend.logAdherenceEvent(
        patientId: patientId,
        patientUid: patientUid,
        medicationId: medicationId,
        eventType: eventType,
        source: source,
        details: details,
      );
  Future<void> logReminderEvent({
    required String patientId,
    String? patientUid,
    required String medicationId,
    required String eventType,
    required String source,
    Map<String, dynamic>? details,
  }) =>
      _backend.logReminderEvent(
        patientId: patientId,
        patientUid: patientUid,
        medicationId: medicationId,
        eventType: eventType,
        source: source,
        details: details,
      );
  Future<void> logUserEngagementEvent({
    String? patientId,
    required String eventType,
    required String source,
    Map<String, dynamic>? details,
  }) =>
      _backend.logUserEngagementEvent(
        patientId: patientId,
        eventType: eventType,
        source: source,
        details: details,
      );
}
